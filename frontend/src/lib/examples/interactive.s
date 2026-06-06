# Interactive I/O - reads a number from you and prints its square.
#
# When you Run this, execution pauses at the read_int ecall: type a number
# into the terminal and press Enter to resume.

.data
prompt: .string "Enter a number: "
answer: .string "Its square is: "
nl:     .string "\n"

.text
main:
        la      a0, prompt      # show the prompt
        li      a7, 4           # syscall 4: print_string
        ecall

        li      a7, 5           # syscall 5: read_int -> a0
        ecall
        mv      t0, a0          # keep the number

        mul     t0, t0, t0      # square it

        la      a0, answer
        li      a7, 4
        ecall

        mv      a0, t0          # print the square
        li      a7, 1           # syscall 1: print_int
        ecall

        la      a0, nl
        li      a7, 4
        ecall

        li      a7, 10          # exit
        ecall
