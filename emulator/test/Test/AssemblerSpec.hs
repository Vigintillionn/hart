module Test.AssemblerSpec (spec) where

import Assembler
import Decoder
import Extension (allExtensions)
import Test.Arbitrary ()
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = do
  describe "Assembler - Decoder" $ do
    it "decoding assembled instruction returns original instruction" $
      withNumTests 10000 $
        property $ \instr ->
          let machineCode = assembleSome instr
              decoded = decodeWord allExtensions machineCode
           in case decoded of
                Right res -> res `shouldBe` instr
                Left err -> expectationFailure $ "Decode failed: " ++ show err
