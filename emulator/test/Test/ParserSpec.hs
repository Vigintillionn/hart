module Test.ParserSpec (spec) where

import Error (AssemblyError (..))
import Extension (ExtensionSet, defaultExtensions, mkExtensionSet)
import Parser (parse)
import Test.Hspec
import Test.Support
import Types

parseErr :: ExtensionSet -> String -> AssemblyError
parseErr exts src = case parse exts src of
  Left e -> underlyingParse e
  Right _ -> error "expected the source to fail parsing"

spec :: Spec
spec = do
  describe "register naming" $ do
    it "accepts ABI register names" $
      realInstrOf "addi a0, sp, 1\n"
        `shouldBe` SomeInstruction (ArithI ADDI (ITypeArgs (reg 10) (reg 2) (ImmVal 1)))

    it "accepts x-prefixed register numbers" $
      realInstrOf "addi x10, x2, 1\n"
        `shouldBe` SomeInstruction (ArithI ADDI (ITypeArgs (reg 10) (reg 2) (ImmVal 1)))

    it "rejects an unknown register" $
      parseErr defaultExtensions "addi a0, x99, 1\n" `shouldBe` InvalidRegister "x99"

  describe "operand forms" $ do
    it "parses the offset(base) memory form of a load" $
      realInstrOf "lw a0, 8(sp)\n"
        `shouldBe` SomeInstruction (LoadI LW (ITypeArgs (reg 10) (reg 2) (ImmVal 8)))

    it "parses a negative immediate" $
      realInstrOf "addi a0, a0, -4\n"
        `shouldBe` SomeInstruction (ArithI ADDI (ITypeArgs (reg 10) (reg 10) (ImmVal (-4))))

    it "ignores comments and surrounding whitespace" $
      realInstrOf "   addi a0, zero, 1   # set a0\n"
        `shouldBe` SomeInstruction (ArithI ADDI (ITypeArgs (reg 10) (reg 0) (ImmVal 1)))

  describe "directives" $ do
    it "parses a .word list" $
      directiveOf ".word 1, 2, 3\n" `shouldBe` DirWord [1, 2, 3]

    it "parses a .string literal with escapes" $
      directiveOf ".string \"hi\\n\"\n" `shouldBe` DirString "hi\n"

  describe "diagnostics" $ do
    it "reports an unknown instruction" $
      parseErr defaultExtensions "frobnicate a0\n" `shouldBe` UnknownInstruction "frobnicate"

    it "reports a mnemonic from a disabled extension" $
      -- mkExtensionSet [] keeps only the mandatory base I set, so M is off
      parseErr (mkExtensionSet []) "mul a0, a1, a2\n"
        `shouldBe` ExtensionDisabled "M" "mul"
