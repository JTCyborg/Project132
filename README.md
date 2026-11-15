# Project132
АТМ турбо 2+ 1024 project

## VGA adapter test

Standalone ATM Turbo 2+ test for the Project131 software VGA/SVGA interface.

- Build: run `build.bat` after placing `sjasmplus.exe` in `tools/`.
- Output: `vga_test.TRD`.
- Test mode: 640×480 RGB565.
- Writes and reads back the 614400-byte framebuffer through the 16 KiB banked aperture.
- Progress and PASS/FAIL result are sent to port `EFh` and recorded in `spectrum_out.txt`.

See [vga_test.asm](vga_test.asm) and [build.bat](build.bat).
