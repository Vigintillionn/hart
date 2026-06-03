module Assembler (assembleSome) where

import Data.Bits (Bits (..))
import Data.Word
import ISA
import Machine
import Types

encodeReg :: Int -> Register -> Word32
encodeReg s r = fromIntegral (unReg r) `shiftL` s

packRd, packRs1, packRs2 :: Register -> Word32
packRd = encodeReg 7
packRs1 = encodeReg 15
packRs2 = encodeReg 20

assembleRType :: Instruction 'R Int -> Word32
assembleRType (RType op args) =
  getOpcode op
    .|. rs1
    .|. rs2
    .|. rd
    .|. (getFunct3 op `shiftL` 12)
    .|. (getFunct7 op `shiftL` 25)
  where
    rd = packRd $ r_rd args
    rs1 = packRs1 $ r_rs1 args
    rs2 = packRs2 $ r_rs2 args

packIType :: Word32 -> Word32 -> Word32 -> ITypeArgs Int -> Word32
packIType opc f3 f7 args =
  opc
    .|. rd
    .|. rs1
    .|. (f3 `shiftL` 12)
    .|. (imm `shiftL` 20)
  where
    rd = packRd $ i_rd args
    rs1 = packRs1 $ i_rs1 args
    rawImm = fromIntegral (i_imm args) .&. 0xFFF
    mask = f7 `shiftL` 5
    imm = rawImm .|. mask

packBImm :: Int -> Word32
packBImm v =
  let i = fromIntegral v :: Word32
      bit12 = (i `shiftR` 12) .&. 0x1
      bit11 = (i `shiftR` 11) .&. 0x1
      bits10_5 = (i `shiftR` 5) .&. 0x3F
      bits4_1 = (i `shiftR` 1) .&. 0xF
   in (bit12 `shiftL` 31)
        .|. (bit11 `shiftL` 7)
        .|. (bits10_5 `shiftL` 25)
        .|. (bits4_1 `shiftL` 8)

packJImm :: Int -> Word32
packJImm v =
  let i = fromIntegral v :: Word32
      bit20 = (i `shiftR` 20) .&. 0x1
      bits10_1 = (i `shiftR` 1) .&. 0x3FF
      bit11 = (i `shiftR` 11) .&. 0x1
      bits19_12 = (i `shiftR` 12) .&. 0xFF
   in (bit20 `shiftL` 31)
        .|. (bits10_1 `shiftL` 21)
        .|. (bit11 `shiftL` 20)
        .|. (bits19_12 `shiftL` 12)

assembleBType :: Instruction 'B Int -> Word32
assembleBType (BType op args) =
  packBImm (b_imm args)
    .|. rs2
    .|. rs1
    .|. (getFunct3 op `shiftL` 12)
    .|. getOpcode op
  where
    rs1 = packRs1 $ b_rs1 args
    rs2 = packRs2 $ b_rs2 args

assembleSType :: Instruction 'S Int -> Word32
assembleSType (SType op args) =
  getOpcode op
    .|. rs1
    .|. rs2
    .|. (immLo `shiftL` 7)
    .|. (getFunct3 op `shiftL` 12)
    .|. (immHi `shiftL` 25)
  where
    imm = fromIntegral $ s_imm args
    immLo = imm .&. 0x1F
    immHi = (imm `shiftR` 5) .&. 0x7F
    rs1 = packRs1 $ s_rs1 args
    rs2 = packRs2 $ s_rs2 args

assembleUType :: Instruction 'U Int -> Word32
assembleUType (UType op args) =
  getOpcode op
    .|. rd
    .|. imm
  where
    rd = packRd $ u_rd args
    imm = fromIntegral $ (u_imm args .&. 0xFFFFF) `shiftL` 12

assembleJType :: Instruction 'J Int -> Word32
assembleJType (JType JAL args) =
  packJImm (j_imm args)
    .|. rd
    .|. 0x6F -- JAL
  where
    rd = packRd (j_rd args)

assembleSystem :: Instruction 'Sys Int -> Word32
assembleSystem (System op args) =
  0x73
    .|. packRd (c_rd args)
    .|. packRs1 (c_rs1 args)
    .|. (getFunct3 op `shiftL` 12)
    .|. (csr `shiftL` 20)
  where
    csr = fromIntegral (c_csr args .&. 0xFFF)
assembleSystem (SystemI op args) =
  0x73
    .|. packRd (ci_rd args)
    .|. (uimm `shiftL` 15)
    .|. (getFunct3 op `shiftL` 12)
    .|. (csr `shiftL` 20)
  where
    csr = fromIntegral (ci_csr args .&. 0xFFF)
    uimm = fromIntegral (ci_uimm args .&. 0x1F)
assembleSystem (Trap op) =
  0x73 .|. (imm `shiftL` 20)
  where
    imm = case op of
      ECALL -> 0
      EBREAK -> 1

assembleSome :: SomeInstruction Int -> Word32
assembleSome (SomeInstruction instr@(RType _ _)) = assembleRType instr
assembleSome (SomeInstruction (ArithI op args)) =
  let safeImm =
        if op `elem` [SLLI, SRLI, SRAI]
          then i_imm args .&. 0x1F
          else i_imm args
      safeArgs = args {i_imm = safeImm}
   in packIType (getOpcode op) (getFunct3 op) (getFunct7 op) safeArgs
assembleSome (SomeInstruction (LoadI op args)) = packIType (getOpcode op) (getFunct3 op) 0x00 args
assembleSome (SomeInstruction (JumpI op args)) = packIType (getOpcode op) (getFunct3 op) 0x00 args
assembleSome (SomeInstruction instr@(BType _ _)) = assembleBType instr
assembleSome (SomeInstruction instr@(SType _ _)) = assembleSType instr
assembleSome (SomeInstruction instr@(UType _ _)) = assembleUType instr
assembleSome (SomeInstruction instr@(JType _ _)) = assembleJType instr
assembleSome (SomeInstruction instr@(System _ _)) = assembleSystem instr
assembleSome (SomeInstruction instr@(SystemI _ _)) = assembleSystem instr
assembleSome (SomeInstruction instr@(Trap _)) = assembleSystem instr

assemble :: Program -> [Word32]
assemble = map assembleSome
