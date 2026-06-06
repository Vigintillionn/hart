# Recursive factorial - computes 5! = 120 using the call stack.
#
# Each call pushes a frame (saving ra and n); step in and watch the stack
# grow downward in the memory view, then unwind as the calls return.

.text
main:
        andi    sp, sp, -16     # 16-byte align the stack pointer first
        li      a0, 5           # compute 5!
        jal     ra, fact

        li      a7, 1           # print the result (120)
        ecall
        li      a7, 10          # exit
        ecall

# fact(n): returns n! in a0
fact:
        addi    sp, sp, -16     # new frame
        sw      ra, 12(sp)      # save return address
        sw      a0, 8(sp)       # save n

        li      t0, 2
        blt     a0, t0, base    # n < 2  ->  return 1

        addi    a0, a0, -1      # recurse on n-1
        jal     ra, fact

        lw      t1, 8(sp)       # t1 = original n
        mul     a0, a0, t1      # a0 = n * fact(n-1)
        j       restore

base:
        li      a0, 1           # 0! = 1! = 1
restore:
        lw      ra, 12(sp)      # restore return address
        addi    sp, sp, 16      # pop the frame
        ret
