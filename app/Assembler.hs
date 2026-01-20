module Assembler where
import Types 
import Data.Word
import Data.Bits (Bits(..))

encodeReg :: Int -> Register -> Word32
encodeReg s r = fromIntegral (unReg r) `shiftL` s 

packRd, packRs1, packRs2 :: Register -> Word32
packRd  = encodeReg 7
packRs1 = encodeReg 15
packRs2 = encodeReg 20

getRFmt :: ROp -> (Word32, Word32, Word32)
getRFmt op = (opc, f3, f7)
    where
        opc = 0x33
        f3  = case op of
            ADD -> 0x0
            SUB -> 0x0
            XOR -> 0x4
            OR  -> 0x6
            AND -> 0x7
        f7  = case op of
            SUB -> 0x20
            _   -> 0x0

assembleRType :: Instruction 'R Int -> Word32
assembleRType (RType op args) =
    opc .|.
    rs1 .|.
    rs2 .|.
    rd  .|.
    (f3 `shiftL` 12) .|.
    (f7 `shiftL` 25)
    where
       (opc, f3, f7) = getRFmt op 
       rd   = packRd  $ r_rd args 
       rs1  = packRs1 $ r_rs1 args  
       rs2  = packRs2 $ r_rs2 args 

getArithFmt :: IArithOp -> Word32 
getArithFmt op = case op of
    ADDI -> 0x0
    XORI -> 0x4
    ORI  -> 0x6 
    ANDI -> 0x7 

getLoadFmt :: ILoadOp -> Word32
getLoadFmt op = case op of 
    LB   -> 0x0 
    LH   -> 0x1 
    LW   -> 0x2

packIType :: Word32 -> Word32 -> ITypeArgs Int -> Word32
packIType opc f3 args =
    opc .|.
    rd .|.
    rs1 .|.
    (f3 `shiftL` 12) .|.
    (imm `shiftL` 20)
    where
        rd          = packRd  $ i_rd args 
        rs1         = packRs1 $ i_rs1 args 
        imm         = fromIntegral (i_imm args) .&. 0xFFF

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
            BLT -> 0x4
            BGE -> 0x5

assembleBType :: Instruction 'B Int -> Word32
assembleBType (BType op args) =
    packBImm  (b_imm args) .|.
    rs2 .|.
    rs1 .|.
    (f3 `shiftL` 12) .|.
    opc
    where
        (opc, f3) = getBFmt op
        rs1 = packRs1 $ b_rs1 args 
        rs2 = packRs2 $ b_rs2 args 

getSFmt :: SOp -> (Word32, Word32)
getSFmt op = (opc, f3)
    where
        opc = 0x23 
        f3 = case op of
            SB -> 0x0
            SH -> 0x1
            SW -> 0x2

assembleSType :: Instruction 'S Int -> Word32
assembleSType (SType op args) =
    opc .|.
    rs1 .|.
    rs2 .|.
    (immLo `shiftL` 7) .|.
    (f3 `shiftL` 12) .|.
    (immHi `shiftL` 25)
    where
        (opc, f3) = getSFmt op
        imm = fromIntegral $ s_imm args
        immLo = imm .&. 0x1F
        immHi = (imm `shiftR` 5) .&. 0x7F
        rs1 = packRs1 $ s_rs1 args 
        rs2 = packRs2 $ s_rs2 args 

assembleSome :: ArchInstr 'Resolved-> Word32
assembleSome (RealInstr (SomeInstruction instr@(RType _ _))) = assembleRType instr
assembleSome (RealInstr (SomeInstruction (ArithI op args)))  = packIType 0x13 (getArithFmt op) args
assembleSome (RealInstr (SomeInstruction (LoadI op args)))   = packIType 0x03 (getLoadFmt op) args
assembleSome (RealInstr (SomeInstruction instr@(BType _ _))) = assembleBType instr
assembleSome (RealInstr (SomeInstruction instr@(SType _ _))) = assembleSType instr

assemble :: Program -> [Word32]
assemble = map assembleSome
