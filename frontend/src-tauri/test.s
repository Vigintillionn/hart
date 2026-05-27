.data
    result: .word 0

.text
_start:
    li t0, 1          # i = 1
    li t1, 10         # limit = 10
    li t2, 0          # sum = 0

loop:
    add t2, t2, t0    # sum += i
    addi t0, t0, 1    # i++
    ble t0, t1, loop  # if i <= 10, continue

    la t3, result     # load address of result
    sw t2, 0(t3)      # store sum
