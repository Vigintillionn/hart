module Test.LinkerSpec (spec) where

import Data.Bits (shiftL)
import Data.IntMap.Strict qualified as IM
import Error (LinkError (..))
import Linker (Executable (..))
import Test.Hspec
import Test.Support
import Types

linkErr :: String -> LinkError
linkErr src = case link src of
  Left e -> underlyingLink e
  Right _ -> error "expected the program to fail linking"

spec :: Spec
spec = do
  describe "label resolution" $ do
    it "resolves a forward branch to a PC-relative offset" $ do
      -- branch at pc 0, target label two instructions later (pc 8)
      let exe = assemble "beq zero, zero, skip\naddi a0, a0, 1\nskip:\naddi a0, a0, 2\n"
      case execProgram exe of
        (SomeInstruction (BType BEQ args) : _) -> b_imm args `shouldBe` 8
        _ -> expectationFailure "expected a BEQ as the first instruction"

    it "reports an undefined label" $
      linkErr "j nowhere\n" `shouldBe` UndefinedLabel "nowhere"

    it "reports a duplicate label" $
      linkErr "foo: nop\nfoo: nop\n" `shouldBe` DuplicateLabel "foo"

  describe "pseudo-instruction lowering" $ do
    it "expands a small li into a single addi" $
      length (execProgram (assemble "li a0, 5\n")) `shouldBe` 1

    it "expands a large li into lui + addi" $
      length (execProgram (assemble "li a0, 0x12345\n")) `shouldBe` 2

    it "sign-extends the lo part when bit 11 is set (li 0xDEADBEEF)" $
      case execProgram (assemble "li a0, 0xDEADBEEF\n") of
        [SomeInstruction (UType LUI hiArgs), SomeInstruction (ArithI ADDI loArgs)] -> do
          u_imm hiArgs `shouldBe` 0xDEADC
          i_imm loArgs `shouldBe` -273
        _ -> expectationFailure "expected li to lower to lui + addi"

    it "lowers nop to addi x0, x0, 0" $
      case execProgram (assemble "nop\n") of
        [SomeInstruction (ArithI ADDI args)] -> do
          i_rd args `shouldBe` reg 0
          i_rs1 args `shouldBe` reg 0
          i_imm args `shouldBe` 0
        _ -> expectationFailure "expected nop to lower to a single addi"

    it "expands call into auipc + jalr" $
      length (execProgram (assemble "call target\ntarget: nop\n")) `shouldBe` 3

    it "lowers csrr to csrrs rd, csr, x0" $
      case execProgram (assemble "csrr a1, mscratch\n") of
        [SomeInstruction (System CSRRS args)] -> do
          c_rd args `shouldBe` reg 11
          c_csr args `shouldBe` 0x340
          c_rs1 args `shouldBe` reg 0
        _ -> expectationFailure "expected csrr to lower to a single csrrs"

    it "lowers csrw to csrrw x0, csr, rs" $
      case execProgram (assemble "csrw mscratch, a1\n") of
        [SomeInstruction (System CSRRW args)] -> do
          c_rd args `shouldBe` reg 0
          c_csr args `shouldBe` 0x340
          c_rs1 args `shouldBe` reg 11
        _ -> expectationFailure "expected csrw to lower to a single csrrw"

  describe "immediate range and alignment checks" $ do
    it "rejects an out-of-range arithmetic immediate" $
      linkErr "addi a0, a0, 5000\n" `shouldBe` ImmOutOfRange "immediate" (-2048) 2047 5000

    it "rejects an out-of-range shift amount" $
      linkErr "slli a0, a0, 40\n" `shouldBe` ShiftOutOfRange 40

  describe "symbols and constants (.equ/.set/.equiv/.globl)" $ do
    it "resolves a .equ constant to its absolute value in an immediate" $
      case execProgram (assemble ".equ FIVE, 5\naddi a0, a0, FIVE\n") of
        [SomeInstruction (ArithI ADDI args)] -> i_imm args `shouldBe` 5
        _ -> expectationFailure "expected a single addi"

    it "lets .equ/.set redefine an earlier constant (last wins)" $
      case execProgram (assemble ".equ X, 1\n.set X, 7\naddi a0, a0, X\n") of
        [SomeInstruction (ArithI ADDI args)] -> i_imm args `shouldBe` 7
        _ -> expectationFailure "expected a single addi"

    it "rejects redefining a .equiv constant" $
      linkErr ".equiv K, 1\n.equiv K, 2\n" `shouldBe` DuplicateLabel "K"

    it "rejects a label that collides with a constant name" $
      linkErr ".equ foo, 1\nfoo: nop\n" `shouldBe` DuplicateLabel "foo"

    it "accepts .globl without affecting resolution" $
      length (execProgram (assemble ".globl main\nmain: nop\n")) `shouldBe` 1

  describe "data emission" $ do
    it "emits .half as two little-endian bytes" $ do
      let dm = execDataMem (assemble ".data\n.half 0x1234\n")
      IM.lookup 0x10000000 dm `shouldBe` Just 0x34
      IM.lookup 0x10000001 dm `shouldBe` Just 0x12

    it "emits .word as four little-endian bytes" $ do
      let dm = execDataMem (assemble ".data\n.word 0xAABBCCDD\n")
      map (`IM.lookup` dm) [0x10000000 .. 0x10000003]
        `shouldBe` [Just 0xDD, Just 0xCC, Just 0xBB, Just 0xAA]

    it "treats .bss as NOBITS (reserves space, emits no bytes) without consuming .data space" $ do
      let dm = execDataMem (assemble ".bss\nbuf: .space 4\n.data\n.word 0xAABBCCDD\n")
      -- bss emitted nothing; the .word still lands at the data base, intact
      IM.lookup 0x10000000 dm `shouldBe` Just 0xDD
      IM.size dm `shouldBe` 4

  describe "expressions" $ do
    it "emits a symbol address with .word (a data relocation)" $ do
      -- target sits one word into .data, i.e. at 0x10000004
      let dm = execDataMem (assemble ".data\nfirst: .word 0\ntarget: .word target\n")
      map (`IM.lookup` dm) [0x10000004 .. 0x10000007]
        `shouldBe` [Just 0x04, Just 0x00, Just 0x00, Just 0x10]

    it "evaluates a difference of symbols in .word" $ do
      let dm = execDataMem (assemble ".data\nstart: .word end - start\nend:\n")
      -- end - start == 4 (one word)
      map (`IM.lookup` dm) [0x10000000 .. 0x10000003]
        `shouldBe` [Just 0x04, Just 0x00, Just 0x00, Just 0x00]

    it "folds an arithmetic expression in an immediate operand" $
      case execProgram (assemble "addi a0, a0, (1 + 2) * 4\n") of
        [SomeInstruction (ArithI ADDI args)] -> i_imm args `shouldBe` 12
        _ -> expectationFailure "expected a single addi"

    it "uses a .equ constant inside an expression" $
      case execProgram (assemble ".equ N, 4\naddi a0, a0, N * 2 + 1\n") of
        [SomeInstruction (ArithI ADDI args)] -> i_imm args `shouldBe` 9
        _ -> expectationFailure "expected a single addi"

    it "evaluates a symbolic .space size at layout time" $ do
      -- buf reserves SIZE(=3) bytes, so the trailing .word lands at 0x10000004
      let dm = execDataMem (assemble ".equ SIZE, 3\n.data\nbuf: .space SIZE\n.align 2\n.word 0xFF\n")
      IM.lookup 0x10000004 dm `shouldBe` Just 0xFF

    it "rejects a .byte value that does not fit in 8 bits" $
      linkErr ".data\n.byte 9999\n" `shouldBe` ImmOutOfRange ".byte value" (-128) 255 9999

    it "rejects a forward symbol in a layout-affecting .space" $
      linkErr ".data\n.space later\nlater:\n" `shouldBe` UndefinedLabel "later"

    it "evaluates division and modulo" $
      case execProgram (assemble "addi a0, a0, 17 / 4 + 17 % 4\n") of
        [SomeInstruction (ArithI ADDI args)] -> i_imm args `shouldBe` 5
        _ -> expectationFailure "expected a single addi"

    it "reports division by zero" $
      linkErr "addi a0, a0, 1 / 0\n" `shouldBe` DivByZero

    it "binds . to the current location in a .equ (sizeof idiom)" $
      case execProgram (assemble ".data\narr: .word 1, 2, 3\n.equ LEN, . - arr\n.text\nli a0, LEN\n") of
        -- LEN == 12 bytes; li of a small constant is a single addi
        [SomeInstruction (ArithI ADDI args)] -> i_imm args `shouldBe` 12
        _ -> expectationFailure "expected li to lower to a single addi"

    it "binds . to the instruction address in a branch target" $
      -- `j .` is an infinite self-loop: offset 0
      case execProgram (assemble "j .\n") of
        [SomeInstruction (JType JAL args)] -> j_imm args `shouldBe` 0
        _ -> expectationFailure "expected a single jal"

  describe "bss layout" $ do
    it "places .bss immediately after .data (no heap collision)" $ do
      -- .data holds one word (4 bytes at 0x10000000..0x10000003); bss follows,
      -- page-aligned, at 0x10001000
      case execProgram (assemble ".data\nd: .word 1\n.bss\nb: .space 4\n.text\nla a0, b\n") of
        [SomeInstruction (UType AUIPC hi), SomeInstruction (ArithI ADDI lo)] -> do
          -- auipc/addi reconstruct b's address (0x10001000) PC-relative from pc 0
          let addr = (u_imm hi `shiftL` 12) + i_imm lo
          addr `shouldBe` 0x10001000
        _ -> expectationFailure "expected la to lower to auipc + addi"

    it "resolves a .equ that references a .bss label to its final address" $ do
      let dm = execDataMem (assemble ".bss\nbuf: .space 4\n.equ BUFADDR, buf\n.data\nptr: .word BUFADDR\n")
      map (`IM.lookup` dm) [0x10000000 .. 0x10000003]
        `shouldBe` [Just 0x00, Just 0x10, Just 0x00, Just 0x10]

  describe "sections" $ do
    it "lays .rodata out ahead of .data in the data region" $ do
      let dm = execDataMem (assemble ".rodata\nr: .word 0xAA\n.data\nd: .word 0xBB\n")
      IM.lookup 0x10000000 dm `shouldBe` Just 0xAA -- rodata first
      IM.lookup 0x10000004 dm `shouldBe` Just 0xBB -- data follows
    it "classifies a writable .section into the data region" $ do
      let dm = execDataMem (assemble ".section .mydata, \"aw\"\nx: .word 0xCC\n")
      IM.lookup 0x10000000 dm `shouldBe` Just 0xCC

    it "reserves a .comm symbol in bss after .data, emitting nothing" $ do
      -- .data holds one word; the common symbol lands page-aligned at 0x10001000
      case execProgram (assemble ".data\nd: .word 1\n.comm buf, 4\n.text\nla a0, buf\n") of
        [SomeInstruction (UType AUIPC hi), SomeInstruction (ArithI ADDI lo)] -> do
          let addr = (u_imm hi `shiftL` 12) + i_imm lo
          addr `shouldBe` 0x10001000
        _ -> expectationFailure "expected la to lower to auipc + addi"

  describe "alignment directives" $ do
    it "treats .balign as a literal byte count" $ do
      -- one byte, then .balign 8 pads to the next 8-byte boundary
      let dm = execDataMem (assemble ".data\n.byte 1\n.balign 8\n.byte 2\n")
      IM.lookup 0x10000008 dm `shouldBe` Just 2

    it "treats .p2align as a power-of-two exponent" $ do
      -- one byte, then .p2align 3 pads to 2^3 = 8
      let dm = execDataMem (assemble ".data\n.byte 1\n.p2align 3\n.byte 2\n")
      IM.lookup 0x10000008 dm `shouldBe` Just 2
