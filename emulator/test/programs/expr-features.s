# ============================================================
#  expr-features.s
#  Exercises the stage-3 expression layer and its follow-ups:
#    - arithmetic/bitwise expressions in operands (+ - * / % << >> & | ^ ~)
#    - the . location counter (.equ LEN, . - array)
#    - character literals ('H', '\n') in .byte and immediates
#    - .word with a symbol address and a symbol difference (data relocations)
#    - .bss laid out after .data (no longer colliding with the heap)
#
#  Expected console output:
#    HART
#    div/mod: 4 1
#    bits: 511
#    len: 20
#    sum: 150
#    bss: 20
#    ptr: 10
#    diff: 20
#    done
# ============================================================

        .equ    WIDTH, 4
        .equ    COUNT, 5
        .equ    PRINT_INT, 1
        .equ    PRINT_STR, 4
        .equ    PRINT_CH, 11
        .equ    EXIT, 10
        .equ    NL, '\n'              # character literal

        .globl  _start

        .text
_start:
        # 0) a .byte string built from character literals -> "HART"
        la      a0, initials
        li      a7, PRINT_STR
        ecall
        call    newline

        # 1) division and modulo: 17 / WIDTH and 17 % WIDTH  ->  4  1
        la      a0, msg_div
        li      a7, PRINT_STR
        ecall
        li      a0, 17 / WIDTH        # 4
        li      a7, PRINT_INT
        ecall
        li      a0, ' '               # character literal as an immediate
        li      a7, PRINT_CH
        ecall
        li      a0, 17 % WIDTH        # 1
        li      a7, PRINT_INT
        ecall
        call    newline

        # 2) bitwise + shift expression: (1 << 8) | 0xFF  ->  511
        la      a0, msg_bits
        li      a7, PRINT_STR
        ecall
        li      a0, (1 << 8) | 0xFF
        li      a7, PRINT_INT
        ecall
        call    newline

        # 3) array length via the . location counter (LEN = . - array)  ->  20
        la      a0, msg_len
        li      a7, PRINT_STR
        ecall
        li      a0, LEN
        li      a7, PRINT_INT
        ecall
        call    newline

        # 4) sum array[0..COUNT-1]  ->  10+20+30+40+50 = 150
        la      a0, msg_sum
        li      a7, PRINT_STR
        ecall
        la      t0, array
        li      t1, COUNT
        li      t2, 0                 # accumulator
        li      t3, 0                 # i
sumloop:
        bge     t3, t1, sumdone
        slli    t4, t3, 2             # i * 4
        add     t5, t0, t4
        lw      t6, 0(t5)
        add     t2, t2, t6
        addi    t3, t3, 1
        j       sumloop
sumdone:
        mv      a0, t2
        li      a7, PRINT_INT
        ecall
        call    newline

        # 5) .bss: store LEN into a reserved slot, read it back  ->  20
        la      a0, msg_bss
        li      a7, PRINT_STR
        ecall
        la      t0, slot
        li      t1, LEN
        sw      t1, 0(t0)
        lw      a0, 0(t0)
        li      a7, PRINT_INT
        ecall
        call    newline

        # 6) .word holding a symbol address (data relocation): *ptr -> array
        la      a0, msg_ptr
        li      a7, PRINT_STR
        ecall
        lw      t0, ptr               # t0 = &array
        lw      a0, 0(t0)             # array[0] = 10
        li      a7, PRINT_INT
        ecall
        call    newline

        # 7) .word holding a symbol difference: diff = arrend - array  ->  20
        la      a0, msg_diff
        li      a7, PRINT_STR
        ecall
        lw      a0, diff
        li      a7, PRINT_INT
        ecall
        call    newline

        la      a0, msg_done
        li      a7, PRINT_STR
        ecall
        li      a7, EXIT
        ecall

# helper placed after an .align so the alignment gap in .text is exercised too
        .align  4
newline:
        li      a0, NL
        li      a7, PRINT_CH
        ecall
        ret

        .data
initials: .byte  'H', 'A', 'R', 'T', 0     # NUL-terminated, via char literals
msg_div:  .string "div/mod: "
msg_bits: .string "bits: "
msg_len:  .string "len: "
msg_sum:  .string "sum: "
msg_bss:  .string "bss: "
msg_ptr:  .string "ptr: "
msg_diff: .string "diff: "
msg_done: .string "done\n"

        .align  2
array:  .word   10, 20, 30, 40, 50
        .equ    LEN, . - array         # . is array + 20 here  ->  LEN = 20
arrend:
ptr:    .word   array                  # address of array (relocated)
diff:   .word   arrend - array         # difference of two symbols  ->  20

        .bss
        .align  2
slot:   .space  4
