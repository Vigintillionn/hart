module Test.ExtensionSpec (spec) where

import Assembler (assembleSome)
import Data.Word (Word32)
import Decoder (decodeWord)
import Error (EmulatorError (..))
import Extension
import Test.Hspec
import Test.Support
import Types

-- | A pre-assembled @mul a0, a1, a2@ word (an M-extension instruction).
mulWord :: Word32
mulWord = assembleSome (SomeInstruction (RType MUL (RTypeArgs (reg 10) (reg 11) (reg 12))))

-- | A pre-assembled @csrrw a0, mscratch, a1@ word (a Zicsr instruction).
csrWord :: Word32
csrWord = assembleSome (SomeInstruction (System CSRRW (SysArgs (reg 10) 0x340 (reg 11))))

spec :: Spec
spec = do
  describe "mkExtensionSet" $ do
    it "always includes the mandatory base I set" $
      isEnabled IExt (mkExtensionSet []) `shouldBe` True

    it "leaves optional extensions off unless requested" $
      isEnabled MExt (mkExtensionSet []) `shouldBe` False

    it "enables an optional extension when asked" $
      isEnabled MExt (mkExtensionSet [MExt]) `shouldBe` True

    it "treats Zicsr as optional, off by default" $
      isEnabled ZicsrExt (mkExtensionSet []) `shouldBe` False

  describe "decoder gating" $ do
    it "rejects a disabled-extension instruction" $
      case decodeWord (mkExtensionSet []) mulWord of
        Left (EDisabledExtension _ _ code) -> code `shouldBe` "M"
        other -> expectationFailure ("expected EDisabledExtension, got: " ++ show other)

    it "accepts the same instruction once the extension is enabled" $
      case decodeWord allExtensions mulWord of
        Right (SomeInstruction (RType MUL _)) -> pure ()
        other -> expectationFailure ("expected a decoded MUL, got: " ++ show other)

    it "rejects a CSR instruction when Zicsr is disabled" $
      case decodeWord (mkExtensionSet []) csrWord of
        Left (EDisabledExtension _ _ code) -> code `shouldBe` "Zicsr"
        other -> expectationFailure ("expected EDisabledExtension, got: " ++ show other)

    it "accepts a CSR instruction once Zicsr is enabled" $
      case decodeWord (mkExtensionSet [ZicsrExt]) csrWord of
        Right (SomeInstruction (System CSRRW _)) -> pure ()
        other -> expectationFailure ("expected a decoded CSRRW, got: " ++ show other)
