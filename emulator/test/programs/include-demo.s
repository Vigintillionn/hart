# ============================================================
#  include-demo.s
#  Exercises the stage-5 .include preprocessing layer: the syscall
#  constants come from a separate file, inlined before parsing. A
#  parse/link error anywhere here still points at include-demo.s
#  (not a flattened line number), thanks to source provenance.
#
#  Expected console output:
#    included: 7
# ============================================================

        .include "io-consts.s"      # pulls in PRINT_INT/PRINT_STR/EXIT/NL

        .globl  _start
        .text
_start:
        la      a0, msg
        li      a7, PRINT_STR
        ecall

        li      a0, 7
        li      a7, PRINT_INT
        ecall

        li      a0, NL              # constant defined in the included file
        li      a7, PRINT_CH
        ecall

        li      a7, EXIT
        ecall

        .data
msg:    .string "included: "
