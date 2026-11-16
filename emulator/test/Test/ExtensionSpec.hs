module Test.ExtensionSpec (spec) where

import Assembler (assembleSome)
import Data.Set qualified as Set
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

-- | A pre-assembled @czero.eqz a0, a1, a2@ word (a Zicond instruction).
czeroWord :: Word32
czeroWord = assembleSome (SomeInstruction (RType CZERO_EQZ (RTypeArgs (reg 10) (reg 11) (reg 12))))

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

  describe "extension requirements" $ do
    let requirementsOf :: Char -> String
        requirementsOf 'd' = "f"
        requirementsOf 'f' = "z"
        requirementsOf _ = ""

    it "enables what a requested extension requires, transitively" $
      withRequirements requirementsOf "d" `shouldBe` Set.fromList "dfz"

    it "adds nothing for an extension without requirements" $
      withRequirements requirementsOf "m" `shouldBe` Set.fromList "m"

    it "terminates on a requirement cycle" $
      withRequirements (\c -> if c == 'a' then "b" else "a") "a" `shouldBe` Set.fromList "ab"

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

    it "rejects a Zicond instruction when Zicond is disabled" $
      case decodeWord (mkExtensionSet []) czeroWord of
        Left (EDisabledExtension _ _ code) -> code `shouldBe` "Zicond"
        other -> expectationFailure ("expected EDisabledExtension, got: " ++ show other)

    it "accepts a Zicond instruction once Zicond is enabled" $
      case decodeWord (mkExtensionSet [ZicondExt]) czeroWord of
        Right (SomeInstruction (RType CZERO_EQZ _)) -> pure ()
        other -> expectationFailure ("expected a decoded CZERO_EQZ, got: " ++ show other)

  describe "Zicond encoding" $
    it "matches the reference encoding of czero.eqz a0, a1, a2" $
      czeroWord `shouldBe` 0x0EC5D533
