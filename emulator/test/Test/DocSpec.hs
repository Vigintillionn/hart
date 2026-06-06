{-# LANGUAGE OverloadedStrings #-}

module Test.DocSpec (spec) where

import Data.Aeson (Value (..), toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.List (nub, sort)
import Doc
  ( FieldDoc (..),
    FormatInfo (..),
    InstructionInfo (..),
    SyscallInfo (..),
    formatCatalogue,
    instructionCatalogue,
    pseudoCatalogue,
    syscallCatalogue,
  )
import Extension (extensionCode, extensionCatalogue)
import Test.Hspec

spec :: Spec
spec = do
  describe "instruction catalogue" $ do
    it "documents at least the RV32IM opcodes" $
      length instructionCatalogue `shouldSatisfy` (>= 50)

    it "gives every instruction a format that exists in the format catalogue" $ do
      let known = map fmtId formatCatalogue
      mapM_
        (\i -> (insnMnemonic i, insnFormat i `elem` known) `shouldBe` (insnMnemonic i, True))
        instructionCatalogue

    it "tags every instruction with a real extension code" $ do
      let codes = map extensionCode extensionCatalogue
      mapM_
        (\i -> (insnMnemonic i, insnExtension i `elem` codes) `shouldBe` (insnMnemonic i, True))
        instructionCatalogue

    it "has no duplicate mnemonics" $ do
      let ms = map insnMnemonic instructionCatalogue
      length (nub ms) `shouldBe` length ms

  describe "instruction-set wire format" $
    it "emits the keys the frontend bindings read" $
      case toJSON (head instructionCatalogue) of
        Object o ->
          mapM_
            (\k -> (k, KM.member k o) `shouldBe` (k, True))
            ["mnemonic", "extension", "format", "operation", "description"]
        v -> expectationFailure ("expected a JSON object, got: " ++ show v)

  describe "format catalogue" $ do
    it "emits the keys the frontend bindings read" $
      case toJSON (head formatCatalogue) of
        Object o ->
          mapM_
            (\k -> (k, KM.member k o) `shouldBe` (k, True))
            ["id", "name", "kind", "syntax", "operands", "fields", "blurb"]
        v -> expectationFailure ("expected a JSON object, got: " ++ show v)

    it "tiles every format's 32 bits with no gaps or overlaps" $
      mapM_
        ( \f ->
            let covered = sort (concatMap (\fld -> [fldLo fld .. fldHi fld]) (fmtFields f))
             in (fmtId f, covered) `shouldBe` (fmtId f, [0 .. 31])
        )
        formatCatalogue

    it "uses only known field roles" $ do
      let roles = ["opcode", "reg", "funct", "imm", "zero"]
      mapM_
        ( \f ->
            mapM_
              (\fld -> (fmtId f, fldRole fld `elem` roles) `shouldBe` (fmtId f, True))
              (fmtFields f)
        )
        formatCatalogue

  describe "pseudo catalogue" $
    it "lists the common pseudo-instructions" $
      length pseudoCatalogue `shouldSatisfy` (>= 20)

  describe "syscall catalogue" $ do
    it "documents the supported syscalls" $
      length syscallCatalogue `shouldSatisfy` (>= 10)

    it "has no duplicate call numbers" $ do
      let codes = map syscallInfoCode syscallCatalogue
      length (nub codes) `shouldBe` length codes

    it "gives every syscall a name and description" $
      mapM_
        (\s -> (syscallInfoName s, null (syscallInfoName s) || null (syscallInfoDescription s)) `shouldBe` (syscallInfoName s, False))
        syscallCatalogue

    it "emits the keys the frontend bindings read" $
      case toJSON (head syscallCatalogue) of
        Object o ->
          mapM_
            (\k -> (k, KM.member k o) `shouldBe` (k, True))
            ["name", "code", "registers", "description"]
        v -> expectationFailure ("expected a JSON object, got: " ++ show v)
