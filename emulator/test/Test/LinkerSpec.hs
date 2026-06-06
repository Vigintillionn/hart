module Test.LinkerSpec (spec) where

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

  describe "immediate range and alignment checks" $ do
    it "rejects an out-of-range arithmetic immediate" $
      linkErr "addi a0, a0, 5000\n" `shouldBe` ImmOutOfRange "immediate" (-2048) 2047 5000

    it "rejects an out-of-range shift amount" $
      linkErr "slli a0, a0, 40\n" `shouldBe` ShiftOutOfRange 40
