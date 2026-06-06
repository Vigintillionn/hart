# Fibonacci - print the first 10 Fibonacci numbers, space-separated.
#
# Watch t0/t1 hold the running pair and t4 the next term as you step.

.data
space:  .string " "
nl:     .string "\n"

.text
main:
        li      t0, 0           # fib(0)
        li      t1, 1           # fib(1)
        li      t2, 10          # how many terms to print
        li      t3, 0           # loop counter
loop:
        beq     t3, t2, done    # printed them all?

        mv      a0, t0          # print the current term
        li      a7, 1           # syscall 1: print_int
        ecall

        la      a0, space       # print a separating space
        li      a7, 4           # syscall 4: print_string
        ecall

        add     t4, t0, t1      # next = fib(n-2) + fib(n-1)
        mv      t0, t1          # shift the pair forward
        mv      t1, t4

        addi    t3, t3, 1       # counter++
        j       loop
done:
        la      a0, nl
        li      a7, 4
        ecall

        li      a7, 10          # exit
        ecall
