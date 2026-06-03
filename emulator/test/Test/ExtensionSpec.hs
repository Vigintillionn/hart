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

spec :: Spec
spec = do
  describe "mkExtensionSet" $ do
    it "always includes the mandatory base I set" $
      isEnabled IExt (mkExtensionSet []) `shouldBe` True

    it "leaves optional extensions off unless requested" $
      isEnabled MExt (mkExtensionSet []) `shouldBe` False

    it "enables an optional extension when asked" $
      isEnabled MExt (mkExtensionSet [MExt]) `shouldBe` True

  describe "decoder gating" $ do
    it "rejects a disabled-extension instruction" $
      case decodeWord (mkExtensionSet []) mulWord of
        Left (EDisabledExtension _ _ code) -> code `shouldBe` "M"
        other -> expectationFailure ("expected EDisabledExtension, got: " ++ show other)

    it "accepts the same instruction once the extension is enabled" $
      case decodeWord allExtensions mulWord of
        Right (SomeInstruction (RType MUL _)) -> pure ()
        other -> expectationFailure ("expected a decoded MUL, got: " ++ show other)
