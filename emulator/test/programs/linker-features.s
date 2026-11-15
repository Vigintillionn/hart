# ============================================================
#  linker-features.s
#  Exercises the stage 1-2 assembler/linker features:
#    - .equ / .set / .equiv absolute constants used as immediates
#    - .globl symbol binding (parsed + recorded)
#    - .data emission of .word / .half / .byte / .string
#    - .bss NOBITS reservation (store then load back)
#    - .align padding inside .text (layout/resolution stay in sync)
#
#  Expected console output:
#    Answer: 42
#    Sum 1..10: 55
#    word=305419896 4660 171
#    bss=777
#    Done!
# ============================================================

        .equ    ANSWER, 42          # .equ constant
        .set    LOOP_N, 10          # .set constant (redefinable form)
        .equiv  PRINT_INT, 1        # .equiv define-once constant (syscall no.)
        .equ    PRINT_STR, 4
        .equ    PRINT_CHAR, 11
        .equ    EXIT, 10
        .equ    NEWLINE, 10         # ascii '\n'

        .globl  _start              # binding directive

        .text
_start:
        # --- "Answer: " + the .equ constant ANSWER (42) ---
        la      a0, msg_answer
        li      a7, PRINT_STR
        ecall
        li      a0, ANSWER          # constant resolves to an absolute immediate
        li      a7, PRINT_INT
        ecall
        call    newline

        # --- sum 1..LOOP_N, bound taken from a .set constant -> 55 ---
        la      a0, msg_sum
        li      a7, PRINT_STR
        ecall
        li      t0, 0               # accumulator
        li      t1, 1               # i
        li      t2, LOOP_N          # loop bound from .set
sum_loop:
        bgt     t1, t2, sum_done    # while i <= N
        add     t0, t0, t1
        addi    t1, t1, 1
        j       sum_loop
sum_done:
        mv      a0, t0
        li      a7, PRINT_INT
        ecall
        call    newline

        # --- read back .data values written as .word/.half/.byte ---
        la      a0, msg_data
        li      a7, PRINT_STR
        ecall
        lw      a0, dword           # global-load pseudo (%hi/%lo of dword)
        li      a7, PRINT_INT
        ecall
        li      a0, 32          # ascii space (char literals are stage 3)
        li      a7, PRINT_CHAR
        ecall
        lhu     a0, dhalf
        li      a7, PRINT_INT
        ecall
        li      a0, 32          # ascii space (char literals are stage 3)
        li      a7, PRINT_CHAR
        ecall
        lbu     a0, dbyte
        li      a7, PRINT_INT
        ecall
        call    newline

        # --- store into .bss then load it back -> 777 ---
        la      a0, msg_bss
        li      a7, PRINT_STR
        ecall
        li      t0, 777
        la      t1, bss_slot
        sw      t0, 0(t1)
        lw      a0, 0(t1)
        li      a7, PRINT_INT
        ecall
        call    newline

        # --- done ---
        la      a0, msg_done
        li      a7, PRINT_STR
        ecall
        li      a7, EXIT
        ecall
        nop

# ------------------------------------------------------------
# A helper placed after an .align so the assembler must pad the
# text section; the call/ret targets must still resolve to the
# real (aligned) address.
# ------------------------------------------------------------
        .align  4                   # pad to a 16-byte boundary
newline:
        li      a0, NEWLINE
        li      a7, PRINT_CHAR
        ecall
        ret

        .data
msg_answer:  .string "Answer: "
msg_sum:     .string "Sum 1..10: "
msg_data:    .string "word="
msg_bss:     .string "bss="
msg_done:    .string "Done!\n"

        .align  2
dword:       .word  0x12345678      # 305419896
dhalf:       .half  0x1234          # 4660
dbyte:       .byte  0xAB            # 171

        .bss
        .align  2
bss_slot:    .space 4
