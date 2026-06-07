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

    it "accepts Windows CRLF line endings, including blank lines" $
      case parse defaultExtensions "li t0, 1\r\n\r\nli t1, 2\r\n" of
        Right stmts -> length stmts `shouldBe` 2
        Left e -> expectationFailure ("expected CRLF source to parse, got: " ++ show e)

  describe "comments" $ do
    let addi = SomeInstruction (ArithI ADDI (ITypeArgs (reg 10) (reg 0) (ImmVal 1)))

    it "ignores a // line comment" $
      realInstrOf "addi a0, zero, 1 // set a0\n" `shouldBe` addi

    it "ignores a full-line // comment above an instruction" $
      realInstrOf "// header\naddi a0, zero, 1\n" `shouldBe` addi

    it "ignores an inline /* */ block comment between operands" $
      realInstrOf "addi a0, /* rd */ zero, 1\n" `shouldBe` addi

    it "ignores a multi-line /* */ block comment" $
      realInstrOf "/* a\n   b */\naddi a0, zero, 1\n" `shouldBe` addi

    it "does not treat /* inside a string literal as a comment" $
      directiveOf ".string \"a /* b\"\n" `shouldBe` DirString "a /* b"

    it "does not treat // inside a string literal as a comment" $
      directiveOf ".string \"http://x\"\n" `shouldBe` DirString "http://x"

    it "reports an unterminated block comment" $
      parseErr defaultExtensions "addi a0, zero, 1 /* oops\n" `shouldBe` EOF

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

    it "reports a CSR pseudo from a disabled extension" $
      -- with Zicsr off, csrr is recognised but reported as disabled, not unknown
      parseErr (mkExtensionSet []) "csrr a0, mscratch\n"
        `shouldBe` ExtensionDisabled "Zicsr" "csrr"

    it "rejects an out-of-range numeric CSR address" $
      parseErr defaultExtensions "csrrw a0, 5000, a1\n"
        `shouldBe` CsrOutOfRange "CSR address" 0 4095 5000

    it "rejects an out-of-range CSR immediate" $
      parseErr defaultExtensions "csrrwi a0, mscratch, 50\n"
        `shouldBe` CsrOutOfRange "CSR immediate" 0 31 50

    it "rejects an li constant that doesn't fit in 32 bits" $
      parseErr defaultExtensions "li t0, 10000000000000\n"
        `shouldBe` ImmediateTooLarge 10000000000000
