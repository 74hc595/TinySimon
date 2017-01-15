;;; TinySimon
;;; Matt Sarnoff (msarnoff.org)
;;; August 7, 2016
;;;
;;; The game of Simon* for the PIC10F200: as of August 2016, this is the
;;; smallest, most space-constrained PIC available. The chip has three general-
;;; purpose I/O pins, one input-only pin, no interrupts, a 2-level deep stack,
;;; 256 words of program space, and 16 bytes of RAM.
;;;
;;; The "Charlieplexing" technique is used to drive four LEDS and one piezo
;;; speaker from three pins. Each of the four I/O pins is connected to a
;;; pushbutton with a pull-up resistor.
;;;
;;; The assignment of buttons to LEDs has been chosen very carefully. When one
;;; of GP0-GP2 goes low, the MCU drives one line high, applying voltage to one
;;; of the LED anodes.
;;;  GP0 goes low: drive GP2 high, light LED 3
;;;  GP1 goes low: drive GP0 high, light LED 1
;;;  GP2 goes low: drive GP0 high, light LED 4
;;; Since GP3 is not multiplexed, when it goes low, the MCU can drive whichever
;;; lines it wants, so we illuminate the remaining LED.
;;;  GP3 goes low: drive GP0 low and GP1 high, light LED 2
;;;
;;; The speaker can be driven by setting GP1 high and GP2 low, or vice versa.
;;;
;;; The PIC10F200 has a single 8-bit free-running timer, Timer0. With the 1:256
;;; prescaler enabled, this is used for delay loops when generating pauses or
;;; tones. When the program starts, we disable the prescaler, and use two timer
;;; readings (one taken when a button is pressed to start the game, and another
;;; when the button is released) as the seed for a 16-bit linear feedback shift
;;; register (LFSR).
;;;
;;; The LFSR is used to generate color sequences without explicitly storing an
;;; array of values in memory. At the start of a sequence of length n, we reset
;;; the LFSR to the initial seed, extract n 2-bit numbers, and light the
;;; appropriate LEDs.
;;; After the sequence has been played, we reset the LFSR again. After each
;;; button press, we extract a 2-bit number from the LFSR and compare it to the
;;; pressed button. If the two match, the previous steps are repeated until the
;;; end of the sequence is reached. If not, the game is over.
;;; After the player has correctly repeated the sequence, the sequence length
;;; is incremented by 1, the LFSR is reset to the initial seed, and the process
;;; is repeated.
;;; The maximum sequence length is 256. If someone is actually capable of
;;; successfully repeating a 256-element sequence, the sequence length resets
;;; to 1. This is simply a design choice; sequences of infinite length can be
;;; generated, though the pattern will repeat every (I think?) 65535 elements.
;;; (the LFSR has a period of 65535; 2 shifts are performed for each element;
;;; after 65535 shifts the LFSR will wrap around but the output sequence will be
;;; shifted by 1 bit; when the LFSR wraps around a second time, the sequence
;;; will start repeating.)
;;;
;;; * "Simon" is a trademark of Hasbro.

  include "p10f200.inc"

  __config _WDTE_OFF & _CP_OFF & _MCLRE_OFF

;;; Delay between sequence elements. Lower numbers increase difficulty.
SEQSPEED    equ 5

;;; GPIO and TRIS bit definitions for GP0, GP1, GP2
GP0_H       equ b'00000001'
GP0_L       equ b'00000000'
GP0_Z       equ b'00000001'
TR0_H       equ b'00000000'
TR0_L       equ b'00000000'
TR0_Z       equ b'00000001'

GP1_H       equ b'00000010'
GP1_L       equ b'00000000'
GP1_Z       equ b'00000010'
TR1_H       equ b'00000000'
TR1_L       equ b'00000000'
TR1_Z       equ b'00000010'

GP2_H       equ b'00000100'
GP2_L       equ b'00000000'
GP2_Z       equ b'00000100'
TR2_H       equ b'00000000'
TR2_L       equ b'00000000'
TR2_Z       equ b'00000100'

;;; GPIO and TRIS values for turning on each output
UNUSED_PINS equ b'11111000'
LED1ON_TRIS equ UNUSED_PINS | TR0_H | TR1_L | TR2_H
LED1ON_GPIO equ UNUSED_PINS | GP0_H | GP1_L | GP2_H

LED2ON_TRIS equ UNUSED_PINS | TR0_L | TR1_H | TR2_L
LED2ON_GPIO equ UNUSED_PINS | GP0_L | GP1_H | GP2_L

LED3ON_TRIS equ UNUSED_PINS | TR0_L | TR1_L | TR2_H
LED3ON_GPIO equ UNUSED_PINS | GP0_L | GP1_L | GP2_H

LED4ON_TRIS equ UNUSED_PINS | TR0_H | TR1_H | TR2_L
LED4ON_GPIO equ UNUSED_PINS | GP0_H | GP1_H | GP2_L

SPKRON_TRIS equ UNUSED_PINS | TR0_Z | TR1_H | TR2_L
SPKRON_GPIO equ UNUSED_PINS | GP0_Z | GP1_H | GP2_L


;;; RAM locations
SEED_L      equ 0x10  ;game random seed, lower byte
SEED_H      equ 0x11  ;game random seed, upper byte
LFSR_L      equ 0x12  ;current LFSR state, lower byte
LFSR_H      equ 0x13  ;current LFSR state, upper byte
SEQLEN      equ 0x14  ;current sequence length
LOOPCOUNT   equ 0x15  ;temporary, used as a loop counter
TMP         equ 0x16  ;temporary
HISCORE     equ 0x17  ;high score (longest completed sequence length)
DELAY       equ 0x1F  ;delay loop counter, lower byte
 
; OSCCAL value was 0x0C24


;;; Program start
  org    0x0000
powerup:
  movwf  OSCCAL
  movlw  22 ;adjusts note tuning so tonedelay4 gives ~987 Hz
  addwf  OSCCAL,f
  movlw  ~((1<<NOT_GPWU)|(1<<T0CS)) ;enable GPIO2 and wakeup on pin change
  option

; If this isn't a wake up from sleep, clear the high score.
  btfss  STATUS,GPWUF
  clrf   HISCORE

init:
; Initialize GPIOs
  call   ledoff
  movfw  GPIO


; Go to sleep and wait for a button press.
; Upon wakeup, the MCU will reset, but the GPWUF flag will be set,
; so the sleep instruction will be skipped and the game will start.
waitforstart:
  btfss  STATUS,GPWUF
  sleep
  bcf    STATUS,GPWUF
; Save the GPIO pin values that triggered the wakeup.
; Later we'll test GP3 to see if we're going to display the current high score,
; but we have wait for the button to be released, and we have to set the timer
; prescaler.
  movfw  GPIO
  movwf  TMP

newgame:
; Create lower byte of random seed from a combination of the previous seed,
; the previous LFSR state (both of which have unknown values on powerup), and
; the timer count.
  movfw  LFSR_L
  xorwf  SEED_L,f
  movfw  TMR0
  xorwf  SEED_L,f
; debounce delay (W=0 gives longest possible delay)
  movlw  0
  call   delay
; wait for the button to be released
  call   waitforrelease
; same as above, but for upper byte of random seed
  movfw  LFSR_H
  xorwf  SEED_H,f
  movfw  TMR0
  xorwf  SEED_H,f
; ensure random seed is not all 0s
  bsf    SEED_H,7
; enable 1:256 Timer0 prescaler
  movlw  ~((1<<NOT_GPWU)|(1<<T0CS)|(1<<PSA))
  option

; If the wakeup was triggered by GP3 going low (the non-multiplexed button)
; display the current high score and go back to sleep.
  movfw  HISCORE
; ...but don't bother if the high score is 0, since nothing will blink and the
; player won't know why the button did nothing. (Just start a game.)
  skpnz
  goto   startanim
  movwf  SEQLEN
  btfss  TMP,3
  goto   showscore

; do a lil light show
startanim:
  movlw  0xF8
  movwf  TMP
startanimloop:
  call   led
  incfsz TMP,f
  goto   startanimloop
  call   longdelay

; initialize game state
  clrf   SEQLEN

;;; Main game loop
loop:
  incf   SEQLEN,f
  call   seqinit

seqloop:
; get next color
  call   rand2bits
  call   led
; previous function returns number of delay iterations in W
  call   delay
; decrement loop count and stop if we're at the end of the sequence
  decfsz LOOPCOUNT,f
  goto   seqloop
  
; reset the LFSR, loop while the player repeats the sequence
  call   seqinit
inputloop:
; get next color
  call   rand2bits
; get player's input
  call   getbutton
; compare two values, game over if they're different
  subwf  TMP,w
  skpz
  goto   gameover
; if the button was correct, light it up
  call   led
; turn LEDs off, wait for the button to be released
  call   waitforrelease
; check next value in sequence
  decfsz LOOPCOUNT,f
  goto   inputloop
; end of seqence, delay before starting the next one
; (waitforrelease returns the delay count in W)
  call   delay
  goto   loop  


; Initializes a sequence.
seqinit:
; reset LFSR
  movfw  SEED_L
  movwf  LFSR_L
  movfw  SEED_H
  movwf  LFSR_H
; reset loop counter
  movfw  SEQLEN
  movwf  LOOPCOUNT
  retlw  0


; Lights up LED 1, 2, 3, or 4 and plays the matching tone based on the value in
; TMP. (0, 1, 2, or 3).
; The return value of SEQSPEED saves a movlw.
led:
  clrf   DELAY
  movfw  TMP
  andlw  b'00000011'
  addwf  PCL,f
; jump table
  goto   led1
  goto   led2
  goto   led3
led4:
  bsf    DELAY,7
led4loop:
  call   led4on
  call   tonedelay4
  call   alloutputslow
  call   tonedelay4
  decfsz DELAY,f
  goto   led4loop
  retlw  SEQSPEED
led1:
  movlw  0x2c
  movwf  DELAY
led1loop:
  call   led1on
  call   tonedelay1
  call   alloutputslow
  call   tonedelay1
  decfsz DELAY,f
  goto   led1loop
  retlw  SEQSPEED
led2:
  bsf    DELAY,6
led2loop:
  call   led2on
  call   tonedelay2
  call   alloutputslow
  call   tonedelay2
  decfsz DELAY,f
  goto   led2loop
  retlw  SEQSPEED
led3:
  movlw  0x56
  movwf  DELAY
led3loop:
  call   led3on
  call   tonedelay3
  call   alloutputslow
  call   tonedelay3
  decfsz DELAY,f
  goto   led3loop
  retlw  SEQSPEED


; Loads a random 2-bit number into TMP.
rand2bits:
  clrf   TMP
  call   randbit
  ; fall through and shift in one more bit

; Left-shifts a random bit into TMP.
randbit:
  ; logical shift right 1 bit
  bcf    STATUS,C
  rrf    LFSR_H,f
  rrf    LFSR_L,f
  ; output bit is now in C;
  ; if it's 1, apply the toggle mask
  movlw  0xB0
  btfsc  STATUS,C
  xorwf  LFSR_H,f
  ; shift the output bit into the output byte
  rlf    TMP,f
  retlw  0


; Waits for a button press, and returns 0, 1, 2, or 3 in W.
; If no input is received after approx. 5 seconds, the invalid value 0xFF is
; returned, ending the game.
getbutton:
  clrf   DELAY
getbuttonloop:
  movlw  b'11111111'
  movwf  GPIO
  tris   GPIO
  call   inputdelay
  btfss  GPIO,3
  retlw  1
  ; For GP0-GP2, test each input in isolation. Pressing a switch may drive
  ; more than one of these inputs low.
  movlw  b'11111001'
  tris   GPIO
  btfss  GPIO,0
  retlw  2
  movlw  b'11111010'
  tris   GPIO
  btfss  GPIO,1
  retlw  0
  movlw  b'11111100'
  tris   GPIO
  btfss  GPIO,2
  retlw  3
  decfsz DELAY,f
  goto   getbuttonloop
  retlw  0xFF


; Turns off LEDs and waits for all buttons to be released.
; Returning 16 saves a movlw.
waitforrelease:
  call   ledoff
  call   shortdelay
  movlw  b'00001111'
  subwf  GPIO,w
  skpz
  goto   waitforrelease
  retlw  16


led1on:
  movlw  LED1ON_TRIS
  tris   GPIO
  movlw  LED1ON_GPIO
  goto   ledcommon
  
led2on:
  movlw  LED2ON_TRIS
  tris   GPIO
  movlw  LED2ON_GPIO
  goto   ledcommon

led3on:
  movlw  LED3ON_TRIS
  tris   GPIO
  movlw  LED3ON_GPIO
  goto   ledcommon

led4on:
  movlw  LED4ON_TRIS
  tris   GPIO
  movlw  LED4ON_GPIO
  goto   ledcommon

alloutputslow:
  clrw
  tris   GPIO
  goto   ledcommon

speakeron:
  movlw  SPKRON_TRIS
  tris   GPIO
  movlw  SPKRON_GPIO
ledcommon:
  movwf  GPIO
; Return 0x7F as it's used by the tonedelayX functions.
  retlw  0x7F

ledoff:
  movlw  0xFF
  tris   GPIO
  movwf  GPIO
  retlw  0

longdelay:
  movlw  12
; fall through

; W indicates the number of iterations desired.
delay:
  movwf  DELAY
delayloop:
  call   shortdelay
  decfsz DELAY,f
  goto   delayloop ;W always 0 after shortdelay returns
  retlw  0


shortdelay: ;128 timer periods
  movlw  0
shortdelayloop:
  movwf  TMR0
  btfss  TMR0,7
  goto   $-1
  retlw  0
tonedelay4: ;note B5, ~987 Hz
  movlw  128-2
  goto   shortdelayloop
tonedelay3: ;note E5, ~659 Hz
  movlw  128-3
  goto   shortdelayloop
tonedelay2: ;note B4, ~494 Hz
  movlw  128-4
  goto   shortdelayloop
tonedelay1: ;note E4, ~330 Hz
  movlw  128-6
  goto   shortdelayloop
tonedelay5:
  movlw  111 ;note B2, ~123 Hz
  goto   shortdelayloop
inputdelay: ;affects input timeout; ~5 sec
  movlw  50
  goto   shortdelayloop


gameover:
  call   waitforrelease
  bsf    DELAY,7
gameoversound:
  call   alloutputslow
  call   tonedelay5
  call   speakeron
  call   tonedelay5
  decfsz DELAY,f
  goto   gameoversound

; Compare the player's score to the high score.
checkhiscore:
; Player's score is the number of successfully repeated sequences,
; so we decrement the length.
  decf   SEQLEN,f
  movfw  SEQLEN
  subwf  HISCORE,w
  skpnc
  goto   showscore
newhiscore:
; Player's score is greater than old high score: play a little fanfare.
  movfw  SEQLEN
  movwf  HISCORE
  clrf   TMP
  bsf    LOOPCOUNT,4
; Alternately blink LEDs 1 and 4.
fanfareloop:
  comf   TMP,f
  call   led
  decfsz LOOPCOUNT,f
  goto   fanfareloop
  call   longdelay

; Blink out the current sequence length on the LEDs.
; Each blink of LED 4 counts 50 (what kind of superhuman could do this?)
; Each blink of LED 3 counts 10
; Each blink of LED 2 counts 5
; Each blink of LED 1 counts 1
showscore:
count50:
  movlw  50
  call   decscore
  addwf  PCL,f
count50ledon:
  call   led4on
  goto   scoreblink
count50done:
count10:
  movlw  10
  call   decscore
  addwf  PCL,f
  call   led3on
  goto   scoreblink
count5:
  movlw  5
  call   decscore
  addwf  PCL,f
  call   led2on
  goto   scoreblink
count1:
  movlw  1
  call   decscore
  addwf  PCL,f
  call   led1on
  goto   scoreblink
; End of score loop: reset.
  goto   init


; Subtracts W from the player's score in SEQLEN.
; If overflow occurs, revert SEQLEN to its old value.
; Return value in W is a jump offset.
decscore:
  subwf  SEQLEN,f
; If an overflow occurs, C flag will be 0.
  skpnc
; No overflow: calling function does not need to jump.
  retlw  0
; Overflow: restore SEQLEN. Calling function will need to jump ahead to break
; out of its loop.
  addwf  SEQLEN,f
  retlw  count50done-count50ledon

; Time out a blink, then jump to the beginning of the score countdown loop.
scoreblink:
  call   longdelay
  call   ledoff
  call   longdelay
  goto   count50

  end
