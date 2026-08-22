#!/usr/bin/env python3
"""Builds assets/demo/demo.prg -- the demo the user picks to see the app work.

WRITTEN, NOT SOURCED. The demo has to be a file the user selects out of
their library, and every C64 program that could serve that purpose is
somebody's. This one is ours: a listing and a 6502 routine written here.

WHY IT IS MACHINE CODE. The demo's whole job is to run on the bundled Open
ROMs, with no Commodore ROM anywhere. Open ROMs is an unfinished
reimplementation, and its BASIC is missing more than you would guess -- as
measured with vice_openroms_demo_test against the bundled build
(DEV.210823.FC.1), rather than assumed:

    PRINT   yes        CHR$        no ("?NOT IMPLEMENTED ERROR")
    POKE    yes        X=5         no  <- no variables at all,
    GOTO    yes        FOR/NEXT    no  <- so no loops either
    SYS     yes

A BASIC demo inside that is barely a demo. So BASIC is used for one line --
"10 SYS 2064", which works -- and the rest is 6502 that writes to screen RAM
and the VIC directly. It calls no KERNAL routine and no BASIC routine, which
means it does not care whose ROMs are fitted: the same file is a working
demo on Open ROMs and on a real dump.

Re-verify after ANY change:
    native/vice_core/linux/build/vice_openroms_demo_test <romdir> demo.prg out.ppm
"""
import pathlib

LOAD_ADDRESS = 0x0801
CODE_ORIGIN = 0x0810  # 2064, the address the BASIC stub SYSes to
SCREEN = 0x0400
COLOUR = 0xD800
TEXT_ROW = 2

# What it says. Twelve rows of forty columns, padded below.
#
# Worded to be true whichever ROMs are fitted: the user may well have a real
# set by the time they open this, and a demo that insists it is running on
# open ROMs when it is not would be its own small lie.
MESSAGE = [
    '     RETRO-C64 DEMO',
    '',
    ' THIS IS A REAL C64.',
    '',
    ' THE APP SHIPS FREE, OPEN SOURCE',
    ' ROMS, SO IT WORKS WITH NOTHING',
    ' SUPPLIED BY YOU.',
    '',
    ' FOR COMMERCIAL GAMES YOU NEED',
    ' THE REAL COMMODORE ONES -',
    ' SEE SETUP TO ADD THEM.',
]


def screen_code(ch):
    """PETSCII to screen code.

    Not the same thing, and getting it wrong is why a naive demo prints
    line-drawing characters: in the default character set 'A'-'Z' are screen
    codes 1-26, while everything from space to '?' happens to match ASCII.
    """
    value = ord(ch.upper())
    if 0x41 <= value <= 0x5A:
        return value - 0x40
    if 0x20 <= value <= 0x3F:
        return value
    return 0x20  # anything else prints as a space rather than as noise


def text_block(rows, size=512):
    """The message as a flat run of screen codes, one 40-column row after
    another, padded with spaces. Sized so the copy loop below is two plain
    256-byte loops with no 16-bit pointer arithmetic."""
    out = bytearray()
    for row in rows:
        line = row[:40].ljust(40)
        out += bytes(screen_code(c) for c in line)
    if len(out) > size:
        raise SystemExit(f'message is {len(out)} bytes, over the {size} budget')
    return bytes(out.ljust(size, b'\x20'))


def basic_stub():
    """10 SYS 2064, tokenised.

    SYS is one of the handful of BASIC keywords Open ROMs implements, which
    is the entire reason the demo is reachable at all: autostart types RUN,
    RUN executes this, and this hands over to the machine code.
    """
    body = bytearray()
    line = bytearray()
    line += b'\x9e'                       # SYS
    line += str(CODE_ORIGIN).encode()     # "2064"
    line += b'\x00'                       # end of line
    next_link = LOAD_ADDRESS + 4 + len(line)
    body += next_link.to_bytes(2, 'little')
    body += (10).to_bytes(2, 'little')    # line number
    body += line
    body += b'\x00\x00'                   # end of program
    return bytes(body)


def code(text_address):
    """The routine itself, hand-assembled.

    Black the screen, clear it, drop the message in, then cycle the border
    forever. Deliberately dull: it has to survive whatever ROM is fitted, so
    it uses no ROM routine at all.
    """
    lo, hi = text_address & 0xFF, text_address >> 8
    return bytes([
        0xA9, 0x00,              # lda #$00
        0x8D, 0x20, 0xD0,        # sta $d020      border black
        0x8D, 0x21, 0xD0,        # sta $d021      background black
        # Clear all 1000 screen bytes and set all 1000 colour bytes to white.
        # Four overlapping 256-byte stores cover 1000 without a 16-bit loop.
        0xA2, 0x00,              # ldx #$00
        0xA9, 0x20,              # lda #$20       space
        0x9D, 0x00, 0x04,        # sta $0400,x
        0x9D, 0x00, 0x05,        # sta $0500,x
        0x9D, 0x00, 0x06,        # sta $0600,x
        0x9D, 0xE8, 0x06,        # sta $06e8,x
        0xA9, 0x01,              # lda #$01       white
        0x9D, 0x00, 0xD8,        # sta $d800,x
        0x9D, 0x00, 0xD9,        # sta $d900,x
        0x9D, 0x00, 0xDA,        # sta $da00,x
        0x9D, 0xE8, 0xDA,        # sta $dae8,x
        0xE8,                    # inx
        0xD0, 0xE1,              # bne -31  (back to the lda #$20 at +10)
        # Copy the 512-byte message block to row 2 of the screen.
        0xA2, 0x00,              # ldx #$00
        0xBD, lo, hi,            # lda text,x
        0x9D, 0x50, 0x04,        # sta $0450,x    row 2
        0xBD, lo, hi + 1,        # lda text+256,x
        0x9D, 0x50, 0x05,        # sta $0550,x
        0xE8,                    # inx
        0xD0, 0xF1,              # bne -15
        # Cycle the border, slowly, forever. The VIC ignores the top nibble,
        # so a plain INC walks the sixteen colours without masking.
        0xEE, 0x20, 0xD0,        # inc $d020
        0xA0, 0x00,              # ldy #$00
        0xA2, 0x00,              # ldx #$00
        0xCA,                    # dex
        0xD0, 0xFD,              # bne -3
        0x88,                    # dey
        0xD0, 0xF8,              # bne -8
        0x4C, 0x00, 0x00,        # jmp cycle -- address patched in below
    ])


def build():
    stub = basic_stub()
    pad = CODE_ORIGIN - (LOAD_ADDRESS + len(stub))
    if pad < 0:
        raise SystemExit('BASIC stub overruns the code origin')
    body = bytearray(stub) + bytes(pad)

    # Two passes: the code needs the address of the text that follows it, and
    # the final JMP needs the address of the cycle loop inside itself.
    placeholder = code(0x1000)
    text_address = CODE_ORIGIN + len(placeholder)
    routine = bytearray(code(text_address))

    # Patch the closing JMP to the "inc $d020" that starts the cycle loop.
    # It is the sixteenth byte from the end: inc(3) ldy(2) ldx(2) dex(1)
    # bne(2) dey(1) bne(2) jmp(3).
    cycle = CODE_ORIGIN + len(routine) - 16
    routine[-2] = cycle & 0xFF
    routine[-1] = cycle >> 8

    body += routine
    body += text_block(MESSAGE)
    return LOAD_ADDRESS.to_bytes(2, 'little') + bytes(body)


if __name__ == '__main__':
    out = pathlib.Path(__file__).resolve().parent.parent / 'assets/demo/demo.prg'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(build())
    print(f'{out} ({out.stat().st_size} bytes)')
