# EMM UART Klipper Test

This is a first communication test for three EMM/ZDT closed-loop stepper
drivers connected to an STM32F407 running Klipper.

## Install

Copy `emm_uart.py` to the Klipper host and `emm_usart.c` into Klipper's
`src/stm32/` directory:

```bash
cp emm_uart.py ~/klipper/klippy/extras/emm_uart.py
cp emm_usart.c ~/klipper/src/stm32/emm_usart.c
```

Add `src-$(CONFIG_MACH_STM32F4) += stm32/emm_usart.c` to
`~/klipper/src/stm32/Makefile`, rebuild and flash the MCU firmware, add the
contents of `emm_uart.cfg` to `printer.cfg`, then restart Klipper.

If the host-side module is installed before the MCU firmware is flashed, set
`enabled: false` in `[emm_uart]` until the new firmware is running.

## Commands

Send the angle-clear command to driver IDs 1, 2, and 3:

```gcode
EMM_CLEAR_ANGLES
```

Run normal Klipper homing first, then clear the EMM driver angle counters:

```gcode
EMM_HOME_AND_CLEAR
```

Send a raw packet for testing:

```gcode
EMM_SEND HEX=010A6D6B READ=4
```

Read realtime positions from IDs 1, 2, and 3:

```gcode
EMM_READ_POSITIONS
```

Run the zero-return angle verification:

```gcode
EMM_VERIFY_ANGLES
```

Default behavior:

1. Run `G28`, then clear the three EMM driver angle counters.
2. Read the current angles as the zero reference.
3. Jog small relative moves in `Z-/Z+` for two cycles.
4. Return to the same command point and read angles again.
5. Report `PASS` if every driver returns within `TOLERANCE` degrees.

Useful conservative test:

```gcode
EMM_VERIFY_ANGLES AXIS=Z DISTANCE=2 CYCLES=1 FEEDRATE=300 TOLERANCE=0.3
```

If you have already homed and cleared angles, skip homing:

```gcode
EMM_VERIFY_ANGLES HOME=0 CLEAR=0
```

## Notes

This module uses STM32F407 hardware USART2: TX=`PA2`, RX=`PA3`. It sends and
receives raw EMM protocol bytes, with no software UART bit encoding.
