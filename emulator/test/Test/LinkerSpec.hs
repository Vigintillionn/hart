module Test.LinkerSpec (spec) where

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
