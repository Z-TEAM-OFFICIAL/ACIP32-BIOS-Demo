; =========================================================================
; ACIP-32 Demo BIOS v1.0 -- boots PROGRAM.CART from any ISO 9660 disc
;
; Flow: splash ("ACIP-32 Demo BIOS") -> progress bar -> parse the root
; directory on sector 20 for "PROGRAM.CART;1" -> verify cart magic ->
; copy the program to its load address -> fade to black -> JMP entry.
; No disc / not found / bad magic / too big all halt on a message screen.
;
; Needs: DISK_INFO Rd (sectors, 0 = empty) and DISK_READ Ra, Rs, Rn
; (Rn sectors from disc offset Rs*2048 to RAM [Ra]).
;
; Register map (R15 is pinned to 0 the whole run):
;   R0  VRAM base (0x100000)      R15 always 0 (also = present-only for GPU_RAST)
;   R1  colours / string addrs    R2  disc sectors
;   R3  directory record pointer  R4  records-left / misc counter
;   R5  found cart LBA            R6  found cart size (bytes)
;   R7  counters (bar, fade)      R8  dest pointer / misc
;   R9  src pointer / entry addr  R10 addr temp
;   R11 value temp                R12 GETBYTE input (byte addr, clobbered)
;   R13 GETBYTE output (byte)     R14 misc temp
; RAM map: SECTBUF 0x10000 (one sector), CARTBUF 0x12000 (cart image).
; Boot code is self-modifying: the entry address is STORed into boot_entry.
; =========================================================================

boot:
        MOVI32 R0, 0x100000
        MOVI32 R15, 0

        ; --- splash background ---
        MOVI32 R1, 0x00081030
        GPU_CLR R0, R1
        MOVI32 R1, 0x00142A50
        MOVI32 R8, 4
        MOVI32 R9, 6
        MOVI32 R10, 56
        MOVI32 R11, 38
        FRECT R8, R9, R10, R11, R1
        MOVI32 R1, 0x0058F01B
        MOVI32 R8, 2
        MOVI32 R9, 2
        MOVI32 R10, 60
        MOVI32 R11, 52
        RECT R8, R9, R10, R11, R1
        MOVI32 R1, 0x00304050
        MOVI32 R8, 7
        MOVI32 R9, 45
        MOVI32 R10, 50
        MOVI32 R11, 6
        RECT R8, R9, R10, R11, R1
        MOVI32 R8, 8
        MOVI32 R9, 12
        CUR_SET R8, R9
        MOVI32 R1, msg_title
        TXT_DISP R1

        ; --- disc present? ---
        DISK_INFO R2
        CMP32 R2, R15
        JZ nodisc

        ; --- progress bar: 25 frames ---
        MOVI32 R7, 0
        MOVI32 R1, 0x0000E5FF
bar:
        MOV R10, R7
        ADD32 R10, R7
        MOVI32 R8, 8
        MOVI32 R9, 46
        MOVI32 R11, 4
        FRECT R8, R9, R10, R11, R1
        GPU_RAST R15
        MOVI32 R14, 1
        ADD32 R7, R14
        MOVI32 R14, 25
        CMP32 R7, R14
        JNZ bar

        MOVI32 R1, msg_loading
        TXT_DISP R1
        GPU_RAST R15

        ; --- read root directory (sector 20) ---
        MOVI32 R8, 0x10000
        MOVI32 R10, 20
        MOVI32 R11, 1
        DISK_READ R8, R10, R11
        MOV R3, R8
        MOVI32 R4, 12

scan:
        MOV R12, R3
        CALL GETBYTE
        CMP32 R13, R15
        JZ notfound
        MOV R10, R3
        MOVI32 R14, 2
        ADD32 R10, R14
        LOAD_RAM R11, R10
        MOV R9, R11
        MOV R10, R3
        MOVI32 R14, 10
        ADD32 R10, R14
        LOAD_RAM R10, R10
        MOV R8, R10
        MOV R10, R3
        MOVI32 R14, 33
        ADD32 R10, R14
        LOAD_RAM R11, R10
        MOVI32 R14, 0x474F5250
        CMP32 R11, R14
        JNZ nextrec
        MOVI32 R14, 4
        ADD32 R10, R14
        LOAD_RAM R11, R10
        MOVI32 R14, 0x2E4D4152
        CMP32 R11, R14
        JNZ nextrec
        MOVI32 R14, 4
        ADD32 R10, R14
        LOAD_RAM R11, R10
        MOVI32 R14, 0x54524143
        CMP32 R11, R14
        JNZ nextrec
        MOV R12, R10
        MOVI32 R14, 4
        ADD32 R12, R14
        CALL GETBYTE
        MOVI32 R14, 0x3B
        CMP32 R13, R14
        JNZ nextrec
        MOV R12, R3
        MOVI32 R14, 38
        ADD32 R12, R14
        CALL GETBYTE
        MOVI32 R14, 0x31
        CMP32 R13, R14
        JNZ nextrec
        MOV R12, R3
        MOVI32 R14, 32
        ADD32 R12, R14
        CALL GETBYTE
        MOVI32 R14, 14
        CMP32 R13, R14
        JNZ nextrec
        MOV R5, R9
        MOV R6, R8
        JMP found

nextrec:
        MOV R12, R3
        CALL GETBYTE
        ADD32 R3, R13
        DEC32 R4
        JNZ scan
        JMP notfound

found:
        ; --- read cart sector 0, parse header ---
        MOVI32 R8, 0x12000
        MOV R10, R5
        MOVI32 R11, 1
        DISK_READ R8, R10, R11
        MOVI32 R10, 0x12000
        LOAD_RAM R11, R10
        MOVI32 R14, 0x50494341
        CMP32 R11, R14
        JNZ badmagic
        MOVI32 R14, 4
        ADD32 R10, R14
        LOAD_RAM R11, R10
        MOVI32 R14, 0x4D493233
        CMP32 R11, R14
        JNZ badmagic
        MOVI32 R10, 0x12000
        MOVI32 R14, 20
        ADD32 R10, R14
        LOAD_RAM R7, R10
        CMP32 R7, R15
        JZ badmagic
        MOVI32 R14, 0xE0000
        CMP32 R14, R7
        JGT sizeok
        JMP toobig

sizeok:
        MOV R10, R7
        MOVI32 R14, 2111
        ADD32 R10, R14
        MOVI32 R14, 2048
        DIV32 R10, R14
        MOVI32 R8, 0x12000
        MOV R11, R5
        DISK_READ R8, R11, R10
        MOVI32 R10, 0x12000
        MOVI32 R14, 12
        ADD32 R10, R14
        LOAD_RAM R8, R10
        MOVI32 R14, 4
        ADD32 R10, R14
        LOAD_RAM R9, R10
        MOV R14, R8
        ADD32 R14, R7
        MOVI32 R10, 0x100000
        CMP32 R10, R14
        JGT copygo
        JMP toobig

copygo:
        MOV R10, R7
        MOVI32 R14, 3
        ADD32 R10, R14
        MOVI32 R14, 4
        DIV32 R10, R14
        MOVI32 R11, 0x12040
copy:
        CMP32 R10, R15
        JZ copy_done
        LOAD_RAM R14, R11
        STOR_RAM R8, R14
        MOVI32 R14, 4
        ADD32 R11, R14
        ADD32 R8, R14
        DEC32 R10
        JMP copy

copy_done:
        MOVI32 R1, msg_start
        TXT_DISP R1
        MOVI32 R7, 12
hold:
        GPU_RAST R15
        DEC32 R7
        JNZ hold
        MOVI32 R10, fade_stream
        MOVI32 R14, 8
        ADD32 R10, R14
        MOVI32 R11, 0
        MOVI32 R8, fade_stream
        MOVI32 R7, 7
        MOVI32 R14, 43
fade:
        STOR_RAM R10, R11
        ADD32 R11, R14
        CVG_RUN R8
        GPU_RAST R15
        DEC32 R7
        JNZ fade
        MOVI32 R1, msg_empty
        TXT_DISP R1
        MOVI32 R10, boot_entry
        MOVI32 R14, 1
        ADD32 R10, R14
        STOR_RAM R10, R9
        JMP boot_entry

nodisc:
        MOVI32 R1, msg_nodisc
        TXT_DISP R1
        GPU_RAST R15
        PWR

notfound:
        MOVI32 R1, msg_notfound
        TXT_DISP R1
        GPU_RAST R15
        PWR

badmagic:
        MOVI32 R1, msg_badmagic
        TXT_DISP R1
        GPU_RAST R15
        PWR

toobig:
        MOVI32 R1, msg_toobig
        TXT_DISP R1
        GPU_RAST R15
        PWR

; --- GETBYTE: R12 = byte address -> R13 = byte value. Clobbers R10,R11,R14.
GETBYTE:
        MOV R10, R12
        MOVI32 R14, 4
        DIV32 R10, R14
        MUL32 R14, R10
        LOAD_RAM R11, R14
        SUB32 R12, R14
        CMP32 R12, R15
        JZ gb_done
        MOVI32 R14, 1
        CMP32 R12, R14
        JZ gb1
        MOVI32 R14, 2
        CMP32 R12, R14
        JZ gb2
        MOVI32 R14, 16777216
        DIV32 R11, R14
        JMP gb_mod
gb2:
        MOVI32 R14, 65536
        DIV32 R11, R14
        JMP gb_mod
gb1:
        MOVI32 R14, 256
        DIV32 R11, R14
        JMP gb_mod
gb_done:
gb_mod:
        MOV R13, R11
        MOVI32 R14, 256
        DIV32 R11, R14
        MUL32 R11, R14
        SUB32 R13, R11
        RET

fade_stream:
        CVG FILL_COLOR 0x000000, 0
        CVG BEGIN
        CVG RECT 0, 0, 256, 144
        CVG FILL
        CVG END

boot_entry:
        JMP 0

msg_title:
        STR "ACIP-32 Demo BIOS\nv1.0  DDR 1MiB  MAX 144p"
msg_loading:
        STR "ACIP-32 Demo BIOS\nSEEK PROGRAM.CART..."
msg_start:
        STR "ACIP-32 Demo BIOS\nSTARTING..."
msg_nodisc:
        STR "ACIP-32 Demo BIOS\nNO DISC IN DRIVE"
msg_notfound:
        STR "ACIP-32 Demo BIOS\nPROGRAM.CART NOT FOUND"
msg_badmagic:
        STR "ACIP-32 Demo BIOS\nBAD CART MAGIC"
msg_toobig:
        STR "ACIP-32 Demo BIOS\nIMAGE TOO BIG"
msg_empty:
        STR ""
