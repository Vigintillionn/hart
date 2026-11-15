# ============================================================
#  section-features.s
#  Exercises the stage-4 generalized section model:
#    - .rodata read-only strings (laid out ahead of .data)
#    - .section name, "flags" custom writable section
#    - .comm / .lcomm common symbols reserved in bss
#    - .balign (byte count) and .p2align (power-of-two exponent)
#
#  Expected console output:
#    sections!
#    comm: 1234
#    lcomm: 5678
#    counter: 99
#    done
# ============================================================

        .equ    PRINT_INT, 1
        .equ    PRINT_STR, 4
        .equ    PRINT_CH, 11
        .equ    EXIT, 10
        .equ    NL, '\n'

        .globl  _start
        .text
_start:
        # --- a string living in .rodata ---
        la      a0, hello
        li      a7, PRINT_STR
        ecall
        call    newline

        # --- a .comm (global) buffer: store then read back -> 1234 ---
        la      a0, msg_comm
        li      a7, PRINT_STR
        ecall
        li      t0, 1234
        la      t1, gbuf
        sw      t0, 0(t1)
        lw      a0, 0(t1)
        li      a7, PRINT_INT
        ecall
        call    newline

        # --- a .lcomm (local) buffer: store then read back -> 5678 ---
        la      a0, msg_lcomm
        li      a7, PRINT_STR
        ecall
        li      t0, 5678
        la      t1, lbuf
        sw      t0, 0(t1)
        lw      a0, 0(t1)
        li      a7, PRINT_INT
        ecall
        call    newline

        # --- a word in a custom writable .section -> 99 ---
        la      a0, msg_sec
        li      a7, PRINT_STR
        ecall
        lw      a0, counter
        li      a7, PRINT_INT
        ecall
        call    newline

        la      a0, msg_done
        li      a7, PRINT_STR
        ecall
        li      a7, EXIT
        ecall

# helper placed after a .balign so a byte-count alignment gap is exercised
        .balign 16
newline:
        li      a0, NL
        li      a7, PRINT_CH
        ecall
        ret

        .rodata
hello:     .string "sections!"
msg_comm:  .string "comm: "
msg_lcomm: .string "lcomm: "
msg_sec:   .string "counter: "
msg_done:  .string "done\n"

        .section .mydata, "aw"
        .p2align 2
counter:   .word 99

        .comm   gbuf, 4
        .lcomm  lbuf, 4
