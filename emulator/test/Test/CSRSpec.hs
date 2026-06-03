module Test.CSRSpec (spec) where

import Test.Hspec
import Test.Support

a1, a2 :: Int
a1 = 11
a2 = 12

mscratch :: Int
mscratch = 0x340

spec :: Spec
spec = do
  describe "register-operand CSR instructions" $ do
    it "csrrw swaps: rd gets the old value, the CSR gets rs1" $ do
      cpu <- runProgram "li a0, 5\ncsrrw a1, mscratch, a0\n"
      regU cpu a1 `shouldBe` 0 -- old value (unset CSR reads 0)
      csr cpu mscratch `shouldBe` 5

    it "csrrs sets the bits named by rs1 (logical OR)" $ do
      cpu <-
        runProgram $
          unlines
            [ "li a0, 0xF0",
              "csrrw zero, mscratch, a0", -- mscratch = 0xF0
              "li a1, 0x0F",
              "csrrs a2, mscratch, a1" -- a2 = old, mscratch |= 0x0F
            ]
      regU cpu a2 `shouldBe` 0xF0
      csr cpu mscratch `shouldBe` 0xFF

    it "csrrc clears the bits named by rs1 (AND complement)" $ do
      cpu <-
        runProgram $
          unlines
            [ "li a0, 0xFF",
              "csrrw zero, mscratch, a0", -- mscratch = 0xFF
              "li a1, 0x0F",
              "csrrc a2, mscratch, a1" -- mscratch &= ~0x0F
            ]
      csr cpu mscratch `shouldBe` 0xF0

  describe "immediate-operand CSR instructions" $ do
    it "csrrwi writes the zero-extended immediate" $ do
      cpu <- runProgram "csrrwi a1, mscratch, 5\n"
      regU cpu a1 `shouldBe` 0
      csr cpu mscratch `shouldBe` 5

    it "csrrsi sets bits from the immediate" $ do
      cpu <-
        runProgram $
          unlines
            [ "csrrwi zero, mscratch, 8", -- mscratch = 0b1000
              "csrrsi zero, mscratch, 1" -- mscratch |= 0b0001
            ]
      csr cpu mscratch `shouldBe` 0x9
