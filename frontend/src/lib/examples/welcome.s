# Welcome to HART - a RISC-V (RV32IM) time-travel debugger.
#
# Press Compile to assemble and Run to execute this program, then use the
# step controls to walk through it forwards AND backwards while the
# registers and memory update live on the right.
#
# A few more example programs are open in the other tabs.

.data
msg:    .string "sum(1..5) = "
nl:     .string "\n"

.text
main:
        la      a0, msg         # address of the string
        li      a7, 4           # syscall 4: print_string
        ecall

        li      t0, 0           # t0 = running sum
        li      t1, 1           # t1 = i (the counter)
        li      t2, 6           # stop once i reaches 6
loop:
        add     t0, t0, t1      # sum += i
        addi    t1, t1, 1       # i++
        blt     t1, t2, loop    # repeat while i < 6

        mv      a0, t0          # print the result...
        li      a7, 1           # syscall 1: print_int
        ecall

        la      a0, nl          # print a newline
        li      a7, 4           # syscall 4: print_string
        ecall

        li      a7, 10          # syscall 10: exit
        ecall
