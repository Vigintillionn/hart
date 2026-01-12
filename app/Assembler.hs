module Assembler where
import Types 
import Data.Word
import Data.Bits (Bits(..))

getImmediate :: Operand -> Int
getImmediate (Label _)     = error "Assembler received unresolved label"
getImmediate (Immediate v) = v

getRFmt :: ROp -> (Word32, Word32, Word32)
getRFmt op = (opc, f3, f7)
    where
        opc = 0x33
        f3  = case op of
            XOR -> 0x4
            OR  -> 0x6
            AND -> 0x7
            _   -> 0x0
        f7  = case op of
            SUB -> 0x20
            _   -> 0x0

assembleRType :: Instruction 'R -> Word32
assembleRType (RType op args) =
    opc .|.
    (rd `shiftL` 7) .|.
    (f3 `shiftL` 12) .|.
    (rs1 `shiftL` 15) .|.
    (rs2 `shiftL` 20) .|.
    (f7 `shiftL` 25)
    where
       (opc, f3, f7) = getRFmt op 
       rd   = fromIntegral $ unReg $ r_rd args
       rs1  = fromIntegral $ unReg $ r_rs1 args
       rs2  = fromIntegral $ unReg $ r_rs2 args 

getIFmt :: IOp -> (Word32, Word32)
getIFmt op = (opc, f3)
    where
        opc = 0x13
        f3  = case op of
            XORI -> 0x4
            ORI  -> 0x6
            ANDI -> 0x7
            _    -> 0x0

assembleIType :: Instruction 'I -> Word32
assembleIType (IType op args) =
    opc .|.
    (rd `shiftL` 7) .|.
    (f3 `shiftL` 12) .|.
    (rs1 `shiftL` 15) .|.
    (imm `shiftL` 20)
    where
        (opc, f3)   = getIFmt op
        rd          = fromIntegral $ unReg $ i_rd args
        rs1         = fromIntegral $ unReg $ i_rs1 args
        imm         = fromIntegral (getImmediate $ i_imm args) .&. 0xFFF

packBImm :: Int -> Word32
packBImm v =
    let i = fromIntegral v :: Word32
        bit12 = (i `shiftR` 12) .&. 0x1
        bit11 = (i `shiftR` 11) .&. 0x1
        bits10_5 = (i `shiftR` 5) .&. 0x3F
        bits4_1  = (i `shiftR` 1) .&. 0xF
    in (bit12 `shiftL` 31) .|.
       (bit11 `shiftL` 7)  .|.
       (bits10_5 `shiftL` 25) .|.
       (bits4_1 `shiftL` 8)

getBFmt :: BOp -> (Word32, Word32)
getBFmt op = (opc, f3)
    where
        opc = 0x63
        f3 = case op of
            BEQ -> 0x0
            BNE -> 0x1

assembleBType :: Instruction 'B -> Word32
assembleBType (BType op args) =
    packBImm  (getImmediate $ b_imm args) .|.
    (rs2 `shiftL` 20) .|.
    (rs1 `shiftL` 15) .|.
    (f3 `shiftL` 12) .|.
    opc
    where
        (opc, f3) = getBFmt op
        rs1 = fromIntegral $ unReg $ b_rs1 args
        rs2 = fromIntegral $ unReg $ b_rs2 args

assembleSome :: SomeInstruction -> Word32
assembleSome (SomeInstruction instr@(RType _ _)) = assembleRType instr
assembleSome (SomeInstruction instr@(IType _ _)) = assembleIType instr
assembleSome (SomeInstruction instr@(BType _ _)) = assembleBType instr

assemble :: [SomeInstruction] -> [Word32]
assemble = map assembleSome
