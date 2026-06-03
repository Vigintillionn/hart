module Test.TrapSpec (spec) where

import Data.Word (Word32)
import Machine (mcause, mtval)
import Test.Hspec
import Test.Support

-- RISC-V exception cause codes.
loadMisaligned, storeMisaligned :: Word32
loadMisaligned = 4
storeMisaligned = 6

spec :: Spec
spec = do
  describe "misaligned load" $ do
    it "traps with cause=4 and records the faulting address in mtval" $ do
      -- 0x201 is not 4-byte aligned, so lw must trap
      cpu <-
        runProgram $
          unlines
            [ "la t0, handler",
              "csrrw zero, mtvec, t0",
              "li t1, 0x201",
              "lw a0, 0(t1)",
              "handler:",
              "li a7, 10",
              "ecall"
            ]
      csr cpu mcause `shouldBe` loadMisaligned
      csr cpu mtval `shouldBe` 0x201

  describe "misaligned store" $ do
    it "traps with cause=6 and records the faulting address in mtval" $ do
      cpu <-
        runProgram $
          unlines
            [ "la t0, handler",
              "csrrw zero, mtvec, t0",
              "li t1, 0x202",
              "li t2, 5",
              "sw t2, 0(t1)",
              "handler:",
              "li a7, 10",
              "ecall"
            ]
      csr cpu mcause `shouldBe` storeMisaligned
      csr cpu mtval `shouldBe` 0x202
