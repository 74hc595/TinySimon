# TinySimon
"Simon" game based on a PIC10F200 microcontroller

![](https://pbs.twimg.com/media/C2CW97UVQAEI9vI.jpg)

This is an implementation of the game "Simon" <sup>[[1]](#f1)</sup> built using a 6-pin Microchip [PIC10F200](http://www.microchip.com/wwwproducts/en/PIC10F200) microcontroller.

The PIC10F200 may be the most resource-constrained microcontroller widely available today. Its specs:

- **Clock speed:** 1 MHz
- **ROM:** 256 instructions (12 bits each)
- **RAM:** 16 bytes
- **Instruction set:** [PIC baseline](https://en.wikipedia.org/wiki/PIC_instruction_listings#Baseline_core_devices_.2812_bit.29)
- **Stack depth:** 2 levels 
- **I/O:** 3 input/output pins, 1 input-only pin
- **Peripherals:** Internal oscillator, one 8-bit free-running timer
- **Interrupts:** None

Despite these restrictions, TinySimon is able to drive 4 LEDs and a piezo buzzer and read 4 switches, powered by one 3V CR2032 coin cell.

Game features:

- **Multicolored LEDs:** Red, yellow, green and blue low-current, low-forward-voltage LEDs.
- **Sound effects:** Four musically-tuned tones, and a low-pitched "game over" tone.
- **No maximum sequence length:** Uses a 16-bit [linear feedback shift register](https://en.wikipedia.org/wiki/Linear-feedback_shift_register) implementation to generate random color sequences.
- **Time limit:** pausing for longer than 5 seconds ends the game
- **Score display:** When the game is over, the player's score (longest sequence length without missing) is flashed out using a color code.
- **High score:** The highest score is kept in memory until the battery is removed.
- **Power saving:** Enters sleep mode when the game is over. Pressing the red, green, or blue button starts a new game. Pressing the yellow button flashes out the high score.

The object of the game is to repeat the randomly-generated sequences of colors/tones by pressing the corresponding buttons. Initially, the player must repeat only a single color. Then, the player must repeat a sequence of two colors. After each successfully repeated sequence, one more color is added. The game is over when the player fails to repeat the sequence correctly or does not press a button within 5 seconds.

At the end of the game, the player's score is flashed out using a color code:

- Each red blink counts 1
- Each yellow blink counts 5
- Each green blink counts 10
- Each blue blink counts 50 (!!!)

If the player has beaten the previous high score, a little fanfare is played out with the red and blue lights flashing alternately.


## Hardware

How does one interface with 4 buttons, 4 switches, *and* a speaker when there are only 4 I/O pins, and one of them is input-only? Using a technique called [Charlieplexing](https://en.wikipedia.org/wiki/Charlieplexing). The three I/O lines are used to drive the LEDs and the speaker. Each I/O line is also connected to a pushbutton. This works well, because every button press causes a corresponding LED to light up. The multiplexing arrangement was carefully chosen to ensure that the correct LED lights up when a given input line is driven to ground.

The LEDs chosen have very low current consumption (very bright when drawing only a milliamp) and very low forward voltages. (~2.65V for the green and blue LEDs!)

The components fit on a double-sided 2 layer board roughly the size of a bottle cap. The battery holder is on the board's underside. I laid out the schematic and PCB in [KiCad](kicad-pcb.org) and had the boards made by the wonderful [OSH Park](oshpark.com).

All components are surface-mount; the resistors and LEDs have 1206 packages, which aren't too difficult to solder by hand. I assembled the board using just a soldering iron, tweezers, flux, 0.032"-diameter solder, and a dab of solder paste for the PIC.

The circuit also fits nicely on a breadboard; the PIC10F200 comes in a DIP-8 package.


## Software

The game was written entirely in PIC assembly language using [MPLAB X](http://www.microchip.com/mplab/mplab-x-ide). Their assembler is free to use, and I used a [PICkit 3](www.microchip.com/pickit3) to flash the chip.

The program's control flow is basically sequential. Nothing is interrupt-driven because the PIC10F200 has no interrupt capability. All delays and tones are generated with busy loops.

The code occupies 253 out of the 256 words of ROM. The program uses just 9 bytes of RAM:

- LFSR seed: 2 bytes
- Current LFSR state: 2 bytes
- Current sequence length ("score"): 1 byte
- High score: 1 byte
- Loop counters and temporaries: 3 bytes

The PIC has no registers to store state in--just one, named W, and it's used by nearly every operation. All game state has to live in RAM. (If I wanted to be sneaky I could use FSR as 5 extra bits of RAM as long as I don't do any indirect memory accesses.)

Lots of fun tricks are used to minimize code size--jumping into the middle of functions, returning constants from functions to save a load instruction, using bit tests instead of numeric comparisons, etc. I could probably shave a few instructions off if I hacked away at it.


## Known limitations

- There are two instances of barely-noticeable LED ghosting: tiny amounts of current flow through the yellow LED when the green button is pressed, and through the blue LED when the "game over" sound is played.
- Pressing multiple buttons at once may have strange effects. I think I've seen this cause the PIC to lock up, and become nonfunctional until the battery is removed and reinserted.


## Code flashing notes

I've added a 5-pad header that corresponds to pins 1-5 of the standard 6-pin ICSP header. However, because the PIC10F200 does not support low-voltage programming, it's not possible to flash the chip when it is running off battery power. I have not had success getting the PICkit 3's "Power Target from Tool" to work; often this just results in the message `"The target has invalid calibration data"`. I recommend two approaches:

1. Remove the battery, solder temporary wires to the positive and negative terminals of the battery holder, and connect an external 5V power supply before flashing.
2. Build a small programming rig and flash the PIC before soldering it. I took an unpopulated board, soldered kynar wires to the ICSP header, and pressed the chip down on its footprint with tweezers during the flashing process. [See this tweet.](https://twitter.com/txsector/status/820902612333535232)


## Enjoy!

Matt Sarnoff ([@txsector](twitter.com/txsector), [msarnoff.org](http://msarnoff.org))

January 14, 2017


### Footnotes

<sup><a name="f1">[1]</a></sup> Simon is a trademark of Hasbro.
