{-# LANGUAGE OverloadedStrings #-}

module Test.WireSpec (spec) where

import Data.Aeson (Value (..), toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Vector.Unboxed qualified as V
import Machine (CPU (..), RunStatus (..), emptyCPU, signedRegs)
import Test.Hspec

spec :: Spec
spec = do
  describe "CpuState wire format" $ do
    it "emits the camelCase keys the frontend bindings read" $
      case toJSON emptyCPU of
        Object o ->
          mapM_
            (\k -> (k, KM.member k o) `shouldBe` (k, True))
            [ "pc",
              "regs",
              "csrs",
              "mem",
              "cycles",
              "status",
              "heapTop",
              "outputBuffer",
              "systemLog",
              "inputBuffer"
            ]
        v -> expectationFailure ("expected a JSON object, got: " ++ show v)

    it "serialises registers as signed 32-bit integers (matches Vec<i32>)" $ do
      let cpu = emptyCPU {regs = regs emptyCPU V.// [(5, 0xFFFFFFFF)]}
      signedRegs cpu !! 5 `shouldBe` (-1)

  describe "RunStatus wire format" $
    it "matches the CpuStatus binding variants verbatim" $ do
      toJSON Running `shouldBe` String "Running"
      toJSON Halted `shouldBe` String "Halted"
      toJSON Paused `shouldBe` String "Paused"
      toJSON WaitingForInput `shouldBe` String "WaitingForInput"
