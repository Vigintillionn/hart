module Decoder (decodeWord) where

import Control.Applicative (liftA3)
import Control.Monad
import Data.Bits (Bits (shiftL, shiftR, (.&.), (.|.)))
import Data.Int (Int32)
import Data.Word (Word32)
import Error (EmulatorError (..))
import Extension (ExtensionSet, extensionCode, isEnabled)
import Extension.Classify (instructionExtension)
import ISA
import Machine
import Types

opMask, rdMask, f3Mask, rs1Mask, rs2Mask, f7Mask, immMask :: (Int, Int)
opMask = (6, 0)
rdMask = (11, 7)
f3Mask = (14, 12)
rs1Mask = (19, 15)
rs2Mask = (24, 20)
f7Mask = (31, 25)
immMask = (31, 20)

-- Extracts bits from 'lo' to 'hi'
slice :: (Int, Int) -> Word32 -> Word32
slice (hi, lo) w =
  let mask = (1 `shiftL` (hi - lo + 1)) - 1
   in (w `shiftR` lo) .&. mask

getRd, getRs1, getRs2 :: Word32 -> Int
getRd w = fromIntegral $ slice rdMask w
getRs1 w = fromIntegral $ slice rs1Mask w
getRs2 w = fromIntegral $ slice rs2Mask w

getOpc, getF3, getF7 :: Word32 -> Word32
getOpc = slice opMask
getF3 = slice f3Mask
getF7 = slice f7Mask

signExtend :: Int -> Word32 -> Int
signExtend bits x =
  let shift = 32 - bits
   in fromIntegral ((fromIntegral x :: Int32) `shiftL` shift `shiftR` shift)

getOp :: (RISCVEncoding a) => Word32 -> Maybe a
getOp = liftA3 matchOp getOpc getF3 getF7

decodeRType :: Word32 -> Maybe (Instruction 'R Int)
decodeRType w = do
  op <- getOp w
  rd <- mkRegister (getRd w)
  rs1 <- mkRegister (getRs1 w)
  rs2 <- mkRegister (getRs2 w)
  return $ RType op (RTypeArgs rd rs1 rs2)

decodeIType :: Word32 -> Word32 -> Maybe (Instruction 'I Int)
decodeIType 0x13 w = do
  let f3 = getF3 w
  op <-
    if f3 == 0x1 || f3 == 0x5
      then getOp w
      else matchOpF3 0x13 f3
  rd <- mkRegister (getRd w)
  rs1 <- mkRegister (getRs1 w)
  let rawImm = slice immMask w

  let imm =
        if op `elem` [SLLI, SRLI, SRAI]
          then fromIntegral (rawImm .&. 0x1F)
          else signExtend 12 rawImm
  return $ ArithI op (ITypeArgs rd rs1 imm)
decodeIType 0x03 w = do
  op <- matchOpF3 0x03 (getF3 w)
  rd <- mkRegister (getRd w)
  rs1 <- mkRegister (getRs1 w)
  let imm = signExtend 12 $ slice immMask w
  return $ LoadI op (ITypeArgs rd rs1 imm)
decodeIType 0x67 w = do
  guard (getF3 w == 0x0)
  rd <- mkRegister (getRd w)
  rs1 <- mkRegister (getRs1 w)
  let imm = signExtend 12 $ slice immMask w
  return $ JumpI JALR (ITypeArgs rd rs1 imm)
decodeIType _ _ = Nothing

unpackBImm :: Word32 -> Int
unpackBImm w =
  signExtend 13 unpacked
  where
    -- B Type immediate is scrambled in the instruction
    bit12 = slice (31, 31) w -- MSB is located at bit 31
    bit11 = slice (7, 7) w -- bit #11 is located at bit 7
    bits10_5 = slice (30, 25) w -- bits 5-10 are located at bits 25-30
    bits4_1 = slice (11, 8) w -- bits 1-4 are located at bits 8-11
    unpacked =
      (bit12 `shiftL` 12)
        .|. (bit11 `shiftL` 11)
        .|. (bits10_5 `shiftL` 5)
        .|. (bits4_1 `shiftL` 1) -- bit 0 is implicitely 0 such that addresses are halfword alligned

unpackJImm :: Word32 -> Int
unpackJImm w = signExtend 21 unpacked
  where
    bit20 = slice (31, 31) w
    bits19_12 = slice (19, 12) w
    bit11 = slice (20, 20) w
    bits10_1 = slice (30, 21) w
    unpacked =
      (bit20 `shiftL` 20)
        .|. (bits19_12 `shiftL` 12)
        .|. (bit11 `shiftL` 11)
        .|. (bits10_1 `shiftL` 1)

decodeBType :: Word32 -> Maybe (Instruction 'B Int)
decodeBType w = do
  op <- matchOpF3 0x63 (getF3 w)
  rs1 <- mkRegister (getRs1 w)
  rs2 <- mkRegister (getRs2 w)
  let imm = unpackBImm w
  return $ BType op (BTypeArgs rs1 rs2 imm)

decodeSType :: Word32 -> Maybe (Instruction 'S Int)
decodeSType w = do
  op <- matchOpF3 0x23 (getF3 w)
  rs1 <- mkRegister $ getRs1 w
  rs2 <- mkRegister $ getRs2 w
  let immHi = getF7 w -- high bits of immediate are in same range as funct7
  let immLo = slice rdMask w -- low bits of immediate are in same rang as rd
  let imm = signExtend 12 $ (immHi `shiftL` 5) .|. immLo
  return $ SType op (STypeArgs rs1 rs2 imm)

decodeUType :: Word32 -> Word32 -> Maybe (Instruction 'U Int)
decodeUType opc w = do
  op <- case opc of
    0x17 -> Just AUIPC
    0x37 -> Just LUI
    _ -> Nothing
  rd <- mkRegister (getRd w)
  let imm = fromIntegral $ slice (31, 12) w
  return $ UType op (UTypeArgs rd imm)

decodeJType :: Word32 -> Maybe (Instruction 'J Int)
decodeJType w = do
  let op = JAL
  rd <- mkRegister (getRd w)
  let imm = unpackJImm w
  return $ JType op (JTypeArgs rd imm)

decodeSystemType :: Word32 -> Maybe (Instruction 'Sys Int)
decodeSystemType w = do
  let f3 = getF3 w
  let imm12 = fromIntegral $ slice immMask w
  rd <- mkRegister (getRd w)
  let rs1Idx = getRs1 w
  rs1Reg <- mkRegister rs1Idx

  case f3 of
    0 -> case imm12 of
      0 -> Just $ Trap ECALL
      1 -> Just $ Trap EBREAK
      _ -> Nothing
    _
      | f3 <= 3 -> (\op -> System op (SysArgs rd imm12 rs1Reg)) <$> matchOpF3 0x73 f3
      | otherwise -> (\op -> SystemI op (SysIArgs rd imm12 rs1Idx)) <$> matchOpF3 0x73 f3

decodeSome :: Word32 -> Maybe (SomeInstruction Int)
decodeSome w =
  let opcode = getOpc w
      instr = case opcode of
        0x33 -> SomeInstruction <$> decodeRType w -- Arithmatic
        0x13 -> SomeInstruction <$> decodeIType opcode w -- Immediate
        0x03 -> SomeInstruction <$> decodeIType opcode w -- Load
        0x67 -> SomeInstruction <$> decodeIType opcode w -- Jump
        0x63 -> SomeInstruction <$> decodeBType w -- Branch
        0x23 -> SomeInstruction <$> decodeSType w -- Store
        0x17 -> SomeInstruction <$> decodeUType opcode w -- AUIPC
        0x37 -> SomeInstruction <$> decodeUType opcode w -- LUI
        0x6F -> SomeInstruction <$> decodeJType w -- JAL
        0x73 -> SomeInstruction <$> decodeSystemType w
        _ -> Nothing
   in instr

-- | The decoder cannot know the program counter, so the 'EDecode' pc field is
-- left 0 here; callers that have a pc (e.g. 'CPU.step') re-attach it.
decodeWord :: ExtensionSet -> Word32 -> Either EmulatorError (SomeInstruction Int)
decodeWord exts w =
  case decodeSome w of
    Just instr
      | isEnabled (instructionExtension instr) exts -> Right instr
      | otherwise ->
          Left (EDisabledExtension 0 w (extensionCode (instructionExtension instr)))
    Nothing -> Left (EDecode 0 w)
