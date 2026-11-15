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
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        CP      $1F
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        CP      $E0
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

        DB      $80
basic_loader_end:

        SAVETRD "vga_test.TRD","boot.B",basic_loader,basic_loader_end-basic_loader,10
        SAVETRD "vga_test.TRD","VGATEST.C",$8000,ProgramEnd-$8000
