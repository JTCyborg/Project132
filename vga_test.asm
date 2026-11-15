; =========================================================================
; PROJECT132 — ATM TURBO 2+ VGA ADAPTER TEST
; Based on the proven ATM startup/ROM trampoline from Project112.
; Target adapter: Project131 ISA VGA/SVGA software interface.
;
; Test:
;   - unlock ATM shadow ports through TR-DOS ROM
;   - enable VGA software mode + 16 KiB aperture
;   - program 640x480 RGB565 through 3E0h/3E1h
;   - fill 614400 bytes of linear VRAM through 38 aperture banks
;   - read back bytes from bank 0 and the last framebuffer bank
;   - report results on port EF (spectrum_out.txt)
;
; Expected image: eight-colour RGB565 vertical bars.
; =========================================================================

        DEVICE ZXSPECTRUM128
        EMPTYTRD "vga_test.TRD"

        ORG     $8000

VgaTestEntry:
        DI
        LD      SP,$BFFF

        LD      HL,MsgBuild
        CALL    DebugPrint
        LD      HL,MsgStart
        CALL    DebugPrint

        CALL    OpenATMShadowPorts

        LD      HL,MsgAdapterInit
        CALL    DebugPrint

        ; 3DEh: software mode = 1, aperture enable = 1, bank 0.
        LD      BC,$03DE
        LD      A,$03
        OUT     (C),A

        ; Configure packed-pixel 640x480 RGB565:
        ; XRES = 0280h, YRES = 01E0h, BPP = 16, ENABLE = 1.
        LD      A,0
        LD      E,$80
        CALL    WriteVgaRegister
        LD      A,1
        LD      E,$02
        CALL    WriteVgaRegister
        LD      A,2
        LD      E,$E0
        CALL    WriteVgaRegister
        LD      A,3
        LD      E,$01
        CALL    WriteVgaRegister
        LD      A,4
        LD      E,16
        CALL    WriteVgaRegister
        LD      A,5
        LD      E,1
        CALL    WriteVgaRegister

        LD      HL,MsgModeSet
        CALL    DebugPrint

        CALL    Fill640x480x16

        LD      HL,MsgFrameWritten
        CALL    DebugPrint

        CALL    VerifyFramebuffer
        OR      A
        JR      NZ,VgaTestFailed

        LD      HL,MsgReadbackPass
        CALL    DebugPrint

        CALL    RunPackedModeSweep

        LD      HL,MsgReady
        CALL    DebugPrint

VgaTestIdle:
        HALT
        JR      VgaTestIdle

VgaTestFailed:
        LD      HL,MsgReadbackFail
        CALL    DebugPrint
VgaTestFailedIdle:
        HALT
        JR      VgaTestFailedIdle

; -------------------------------------------------------------------------
; ATM Turbo 2+ shadow-port unlock, copied from the working Project112 flow.
; TR-DOS ROM entry #3D2F calls OUT (C),A at #2A53.
; -------------------------------------------------------------------------
OpenATMShadowPorts:
        LD      BC,ShadowPortsOpened
        PUSH    BC
        LD      BC,$2A53
        PUSH    BC
        LD      BC,$0177
        LD      A,$C3
        JP      $3D2F
ShadowPortsOpened:
        RET

; A = indexed VGA register, E = value.
WriteVgaRegister:
        LD      BC,$03E0
        OUT     (C),A
        LD      A,E
        INC     C
        OUT     (C),A
        RET

; -------------------------------------------------------------------------
; Fill the 640x480x16 framebuffer.
; Size = 614400 bytes = 37 full 16 KiB banks + 8192 bytes in bank 37.
; The aperture C000h-FFFFh is switched with port 3DFh.
; -------------------------------------------------------------------------
Fill640x480x16:
        XOR     A
        LD      (CurrentBank),A

FillBankLoop:
        LD      A,(CurrentBank)
        LD      BC,$03DF
        OUT     (C),A

        LD      HL,$C000
        LD      DE,ColorPattern
        LD      A,(CurrentBank)
        CP      37
        JR      Z,FillLastHalfBank
        LD      BC,$4000
        JR      FillBankBytes

FillLastHalfBank:
        LD      BC,$2000

FillBankBytes:
        LD      A,(DE)
        INC     DE
        LD      (HL),A
        INC     HL

        ; Repeat the 128-byte RGB565 colour-bar sequence.
        PUSH    AF
        LD      A,D
        CP      HIGH ColorPatternEnd
        JR      NZ,PatternPointerReady
        LD      A,E
        CP      LOW ColorPatternEnd
        JR      NZ,PatternPointerReady
        LD      DE,ColorPattern
PatternPointerReady:
        POP     AF

        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,FillBankBytes

        LD      A,(CurrentBank)
        INC     A
        LD      (CurrentBank),A
        CP      38
        JR      NZ,FillBankLoop
        RET

; -------------------------------------------------------------------------
; Readback checks:
; bank 0 starts with 00 00 1F 00 E0 07 FF 07.
; bank 37 starts at linear offset 37*4000h = 5E000h.
; The final byte of the 640x480 framebuffer is bank 37 offset 1FFFh = FF.
; Return A=0 on success, A=1 on mismatch.
; -------------------------------------------------------------------------
VerifyFramebuffer:
        XOR     A
        LD      BC,$03DF
        OUT     (C),A

        LD      HL,$C000
        ; First eight pixels are black: bytes 0..15 must be zero.
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed

        ; Pixel 8 begins the blue RGB565 bar: 1F 00.
        LD      HL,$C010
        LD      A,(HL)
        CP      $1F
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed

        LD      A,37
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$DFFF
        LD      A,(HL)
        CP      $FF
        JR      NZ,VerifyFailed

        XOR     A
        RET

VerifyFailed:
        LD      A,1
        RET


; -------------------------------------------------------------------------
; Sweep every packed-pixel mode accepted by the Project131 1 MiB adapter.
; Supported combinations are taken from docs/ISA_VGA_Adapter.md.
; Each mode is selected, the entire 1 MiB aperture is written, then held
; briefly so the VGA window can be inspected before advancing.
; -------------------------------------------------------------------------
RunPackedModeSweep:
        LD      HL,MsgSweepStart
        CALL    DebugPrint
        LD      HL,PackedModeTable
        LD      (ModeTablePtr),HL
        LD      A,13
        LD      (ModeCount),A

PackedModeNext:
        LD      HL,(ModeTablePtr)
        LD      A,(HL)
        INC     HL
        LD      (ModeXLo),A
        LD      A,(HL)
        INC     HL
        LD      (ModeXHi),A
        LD      A,(HL)
        INC     HL
        LD      (ModeYLo),A
        LD      A,(HL)
        INC     HL
        LD      (ModeYHi),A
        LD      A,(HL)
        INC     HL
        LD      (ModeBpp),A
        LD      (ModeTablePtr),HL

        LD      A,0
        LD      A,(ModeXLo)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,1
        LD      A,(ModeXHi)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,2
        LD      A,(ModeYLo)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,3
        LD      A,(ModeYHi)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,4
        LD      A,(ModeBpp)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,5
        LD      E,1
        CALL    WriteVgaRegister

        LD      HL,MsgModePrefix
        CALL    DebugPrint
        LD      A,(ModeXHi)
        CALL    DebugHexByte
        LD      A,(ModeXLo)
        CALL    DebugHexByte
        LD      A,'x'
        OUT     ($EF),A
        LD      A,(ModeYHi)
        CALL    DebugHexByte
        LD      A,(ModeYLo)
        CALL    DebugHexByte
        LD      A,' '
        OUT     ($EF),A
        LD      A,(ModeBpp)
        CALL    DebugHexByte
        LD      HL,MsgBppSuffix
        CALL    DebugPrint

        CALL    FillModeVRAM
        ; Draw the standard Spectrum ROM 8x8 font into the packed framebuffer.
        CALL    DrawSpectrumBanner
        CALL    ModeHoldDelay

        LD      A,(ModeCount)
        DEC     A
        LD      (ModeCount),A
        JP      NZ,PackedModeNext
        LD      HL,MsgSweepDone
        CALL    DebugPrint
        RET

; Fill 1 MiB with a repeating RGB/index-friendly byte pattern.
; All 64 banks are written so the test covers the full VRAM aperture.
FillModeVRAM:
        XOR     A
        LD      (CurrentBank),A
ModeFillBank:
        LD      A,(CurrentBank)
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$C000
        LD      DE,ModePattern
        LD      BC,$4000
ModeFillByte:
        LD      A,(DE)
        INC     DE
        LD      (HL),A
        INC     HL
        LD      A,D
        CP      HIGH ModePatternEnd
        JR      NZ,ModePatternReady
        LD      A,E
        CP      LOW ModePatternEnd
        JR      NZ,ModePatternReady
        LD      DE,ModePattern
ModePatternReady:
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,ModeFillByte
        LD      A,(CurrentBank)
        INC     A
        LD      (CurrentBank),A
        CP      64
        JR      NZ,ModeFillBank
        RET

ModeHoldDelay:
        LD      DE,$FFFF
ModeHoldLoop:
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,ModeHoldLoop
        RET

; -------------------------------------------------------------------------
; Draw "P132 VGA TEST" with the Spectrum ROM character set.
; The standard 8x8 ROM font starts at 3D00h (character 32).
; Draws one 104-pixel line at the top of bank 0. The chosen modes keep
; the complete 8 scanlines inside the first 16 KiB aperture bank.
; -------------------------------------------------------------------------
DrawSpectrumBanner:
        ; Select framebuffer bank zero.
        XOR     A
        LD      BC,$03DF
        OUT     (C),A

        ; Bytes per pixel: ceil(BPP/8).
        LD      A,(ModeBpp)
        CP      8
        LD      A,1
        JR      Z,DrawBytesReady
        LD      A,(ModeBpp)
        CP      16
        LD      A,2
        JR      C,DrawBytesReady
        JR      Z,DrawBytesReady
        LD      A,(ModeBpp)
        CP      24
        LD      A,3
        JR      C,DrawBytesReady
        JR      Z,DrawBytesReady
        LD      A,4
DrawBytesReady:
        LD      (DrawBytes),A

        ; Calculate pitch = X resolution * bytes per pixel.
        LD      A,(ModeXLo)
        LD      L,A
        LD      A,(ModeXHi)
        LD      H,A
        EX      DE,HL
        LD      HL,0
        LD      A,(DrawBytes)
DrawPitchLoop:
        ADD     HL,DE
        DEC     A
        JR      NZ,DrawPitchLoop
        LD      (DrawPitch),HL

        XOR     A
        LD      (DrawRow),A
        LD      (DrawRowBase),A
        LD      (DrawRowBase+1),A

DrawBannerRow:
        ; Start this scanline at C000h + row * pitch.
        LD      HL,(DrawRowBase)
        LD      DE,$C000
        ADD     HL,DE
        LD      (DrawPixelPtr),HL
        LD      HL,DrawBannerText
        LD      (DrawStringPtr),HL

DrawBannerChar:
        LD      HL,(DrawStringPtr)
        LD      A,(HL)
        OR      A
        JR      Z,DrawBannerRowDone
        INC     HL
        LD      (DrawStringPtr),HL

        ; Font address = 3D00h + (ASCII - 20h) * 8 + scanline.
        SUB     32
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,$3D00
        ADD     HL,DE
        LD      A,(DrawRow)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      A,(HL)
        LD      (DrawGlyphBits),A
        LD      A,8
        LD      (DrawPixelCount),A

DrawBannerPixel:
        LD      A,(DrawGlyphBits)
        RLCA
        LD      (DrawGlyphBits),A
        LD      A,0
        JR      NC,DrawBannerPixelInkReady
        LD      A,1
DrawBannerPixelInkReady:
        LD      (DrawInk),A
        CALL    DrawBannerPutPixel
        LD      A,(DrawPixelCount)
        DEC     A
        LD      (DrawPixelCount),A
        JR      NZ,DrawBannerPixel
        JR      DrawBannerChar

DrawBannerRowDone:
        LD      HL,(DrawRowBase)
        LD      DE,(DrawPitch)
        ADD     HL,DE
        LD      (DrawRowBase),HL
        LD      A,(DrawRow)
        INC     A
        LD      (DrawRow),A
        CP      8
        JR      NZ,DrawBannerRow
        RET

; Write one foreground/background pixel and advance the linear pointer.
DrawBannerPutPixel:
        LD      HL,(DrawPixelPtr)
        LD      A,(DrawInk)
        OR      A
        JR      Z,DrawBannerBackground
        LD      A,(ModeBpp)
        CP      8
        LD      A,$FF
        JR      NZ,DrawBannerPixelValueReady
        LD      A,$0F               ; EGA palette entry 15 = white.
        JR      DrawBannerPixelValueReady
DrawBannerBackground:
        XOR     A
DrawBannerPixelValueReady:
        LD      C,A
        LD      A,(DrawBytes)
        LD      B,A
        LD      A,C
DrawBannerPutPixelByte:
        LD      (HL),A
        INC     HL
        DJNZ    DrawBannerPutPixelByte
        LD      (DrawPixelPtr),HL
        RET

DrawBannerText:
        DEFM    "P132 VGA TEST",0

DebugHexByte:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    DebugHexNibble
        POP     AF
        CALL    DebugHexNibble
        RET
DebugHexNibble:
        AND     $0F
        ADD     A,'0'
        CP      '9'+1
        JR      C,DebugHexOut
        ADD     A,7
DebugHexOut:
        OUT     ($EF),A
        RET

; -------------------------------------------------------------------------
; Port EF text logger (ASCII bytes, same convention as Project112).
; -------------------------------------------------------------------------
DebugPrint:
        LD      A,(HL)
        OR      A
        RET     Z
        OUT     ($EF),A
        INC     HL
        JR      DebugPrint

CurrentBank: DB 0


ModeTablePtr: DW 0
ModeCount:    DB 0
ModeXLo:      DB 0
ModeXHi:      DB 0
ModeYLo:      DB 0
ModeYHi:      DB 0
ModeBpp:      DB 0
DrawBytes:    DB 0
DrawRow:      DB 0
DrawPixelCount: DB 0
DrawGlyphBits: DB 0
DrawInk:      DB 0
DrawPitch:    DW 0
DrawRowBase:  DW 0
DrawPixelPtr: DW 0
DrawStringPtr: DW 0

ModePattern:
        DB $00,$00,$1F,$00,$E0,$07,$FF,$07,$00,$F8,$1F,$F8,$E0,$FF,$FF,$FF
ModePatternEnd:

; All and only the packed modes that fit in the adapter's 1 MiB VRAM.
; Entry: X low, X high, Y low, Y high, bits per pixel.
PackedModeTable:
        DB 320&255,320>>8,200&255,200>>8,8
        DB 320&255,320>>8,200&255,200>>8,15
        DB 320&255,320>>8,200&255,200>>8,16
        DB 320&255,320>>8,200&255,200>>8,24
        DB 320&255,320>>8,200&255,200>>8,32
        DB 640&255,640>>8,480&255,480>>8,8
        DB 640&255,640>>8,480&255,480>>8,15
        DB 640&255,640>>8,480&255,480>>8,16
        DB 640&255,640>>8,480&255,480>>8,24
        DB 800&255,800>>8,600&255,600>>8,8
        DB 800&255,800>>8,600&255,600>>8,15
        DB 800&255,800>>8,600&255,600>>8,16
        DB 1024&255,1024>>8,768&255,768>>8,8

ColorPattern:
        ; Eight RGB565 colours, each repeated for eight adjacent pixels.
        ; This makes eight visible bars, repeated across the 640-pixel row.
        DB $00,$00, $00,$00, $00,$00, $00,$00, $00,$00, $00,$00, $00,$00, $00,$00
        DB $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00
        DB $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07
        DB $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07
        DB $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8
        DB $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8
        DB $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF
        DB $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF
ColorPatternEnd:

MsgBuild:        DEFM "P132 VGA TEST ATM710",13,10,0
MsgStart:        DEFM "ATM VGA ADAPTER TEST START",13,10,0
MsgAdapterInit:  DEFM "VGA SOFTWARE MODE ON",13,10,0
MsgModeSet:      DEFM "MODE 640X480 RGB565 SET",13,10,0
MsgFrameWritten: DEFM "VRAM 614400 BYTES WRITTEN",13,10,0
MsgReadbackPass: DEFM "VRAM READBACK PASS",13,10,0
MsgReadbackFail: DEFM "VRAM READBACK FAIL",13,10,0
MsgReady:        DEFM "VGA TEST COMPLETE - CHECK VGA WINDOW",13,10,0
MsgSweepStart:   DEFM "PACKED SVGA MODE SWEEP START",13,10,0
MsgModePrefix:   DEFM "MODE ",0
MsgBppSuffix:    DEFM " BPP - VRAM TEST",13,10,0
MsgSweepDone:    DEFM "PACKED SVGA MODE SWEEP DONE",13,10,0

ProgramEnd:

; =========================================================================
; TR-DOS BASIC loader. Loads VGATEST.C at 8000h and starts it.
; =========================================================================
        ORG     $B000
CLEAR       EQU $FD
LOAD        EQU $EF
CODE        EQU $AF
REM         EQU $EA
RANDOMIZE   EQU $F9
USR         EQU $C0
OUT_CMD     EQU $DF
VAL         EQU $B0

basic_loader:
        DB      0,10
        DW      l10_len
l10:    DB      OUT_CMD, "239", $0E, $00, $00, $EF, $00, $00, ",", "1", $0E, $00, $00, $01, $00, $00, ":", CLEAR, "32767", $0E, $00, $00, $7F, $FF, $00, $0D
l10_len EQU     $-l10

        DB      0,20
        DW      l20_len
l20:    DB      RANDOMIZE, USR, "15619", $0E, $00, $00
        DW      15619
        DB      0, $3A, REM, $3A, "LOAD ", 34, "VGATEST", 34, " CODE 32768", $0D
l20_len EQU     $-l20

        DB      0,30
        DW      l30_len
l30:    DB      RANDOMIZE, USR, "32768", $0E, $00, $00
        DW      32768
        DB      $0D
l30_len EQU     $-l30

        DB      $80
basic_loader_end:

        SAVETRD "vga_test.TRD","boot.B",basic_loader,basic_loader_end-basic_loader,10
        SAVETRD "vga_test.TRD","VGATEST.C",$8000,ProgramEnd-$8000
