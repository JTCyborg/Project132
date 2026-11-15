# Project132 — ATM Turbo 2+ VGA adapter test

Standalone ATM Turbo 2+ test program, based on the proven startup and TR-DOS shadow-port unlock sequence in Project112.

The guest program targets the software VGA/SVGA interface implemented by Project131. It does **not** use the transparent video-capture path.

## Build

1. Copy `sjasmplus.exe` from `Project112/tools/` into `Project132/tools/`.
2. Run `build.bat`.
3. Use the generated `vga_test.TRD` in Unreal Speccy with the ATM Turbo 2+ configuration.

## Test performed

- Opens ATM shadow ports using the Project112 TR-DOS ROM trampoline.
- Enables VGA software mode and the 16 KiB aperture with port `03DEh = 03h`.
- Programs the custom packed-pixel extension at `03E0h/03E1h`: 640 × 480, 16 bpp RGB565.
- Writes the complete 614400-byte framebuffer through aperture banks 0–37.
- Reads back the first bytes from bank 0 and the last visible byte from bank 37.
- Sends progress and PASS/FAIL messages to port `EFh`.

Expected picture: eight RGB565 vertical colour bars in the separate **ISA VGA Adapter** window.

## Important

The Project131 adapter is a software VGA/SVGA model with 1 MiB VRAM and a project-specific packed-pixel extension. It is not a full VGA BIOS/VBE-compatible physical card. The program tests the documented Project131 programming interface, not arbitrary DOS VGA software.

If the VGA window stays blank, check that `[ISA_VGA]` has `Enabled=1` in the emulator's `unreal.ini`, restart the emulator, and inspect `spectrum_out.txt` for the port EF result.
