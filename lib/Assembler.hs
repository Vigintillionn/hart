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
            SLL -> 0x1
            SRL -> 0x5
            SRA -> 0x5
            SLT -> 0x2
            SLTU -> 0x3
        f7  = case op of
            SUB -> 0x20
            SRA -> 0x20
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

getArithFmt :: IArithOp -> (Word32, Word32) 
getArithFmt op = (f3, f7)
    where
        f3 = case op of
            ADDI  -> 0x0
            XORI  -> 0x4
            ORI   -> 0x6
            ANDI  -> 0x7
            SLLI  -> 0x1
            SRLI  -> 0x5
            SRAI  -> 0x5
            SLTI  -> 0x2
            SLTIU -> 0x3
        f7 = if op == SRAI then 0x20 else 0x00

getLoadFmt :: ILoadOp -> Word32
getLoadFmt op = case op of 
    LB   -> 0x0 
    LH   -> 0x1 
    LW   -> 0x2
    LBU  -> 0x4
    LHU  -> 0x5

packIType :: Word32 -> (Word32, Word32) -> ITypeArgs Int -> Word32
packIType opc (f3, f7) args =
    opc .|.
    rd .|.
    rs1 .|.
    (f3 `shiftL` 12) .|.
    (imm `shiftL` 20) 
    where
        rd          = packRd  $ i_rd args 
        rs1         = packRs1 $ i_rs1 args 
        rawImm = fromIntegral (i_imm args) .&. 0xFFF
        mask   = f7 `shiftL` 5
        imm    = rawImm .|. mask 

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

packJImm :: Int -> Word32
packJImm v =
    let i = fromIntegral v :: Word32
        bit20    = (i `shiftR` 20) .&. 0x1
        bits10_1 = (i `shiftR` 1)  .&. 0x3FF
        bit11    = (i `shiftR` 11) .&. 0x1
        bits19_12= (i `shiftR` 12) .&. 0xFF
    in (bit20     `shiftL` 31) .|.
       (bits10_1  `shiftL` 21) .|.
       (bit11     `shiftL` 20) .|.
       (bits19_12 `shiftL` 12)

getBFmt :: BOp -> (Word32, Word32)
getBFmt op = (opc, f3)
    where
        opc = 0x63
        f3 = case op of
            BEQ  -> 0x0
            BNE  -> 0x1
            BLT  -> 0x4
            BGE  -> 0x5
            BLTU -> 0x6 
            BGEU -> 0x7

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

assembleUType :: Instruction 'U Int -> Word32
assembleUType (UType op args) =
    opc .|.
    rd  .|.
    imm 
    where
        opc = case op of
            AUIPC -> 0x17
            LUI   -> 0x37
        rd  = packRd $ u_rd args 
        imm = fromIntegral $ (u_imm args .&. 0xFFFFF) `shiftL` 12

assembleJType :: Instruction 'J Int -> Word32
assembleJType (JType JAL args) =
    packJImm (j_imm args) .|.
    rd .|.
    0x6F -- JAL
    where
        rd = packRd (j_rd args)

assembleSome :: SomeInstruction Int -> Word32
assembleSome (SomeInstruction instr@(RType _ _)) = assembleRType instr
assembleSome (SomeInstruction (ArithI op args))  = 
    let safeImm = if op `elem` [SLLI, SRLI, SRAI]
                  then i_imm args .&. 0x1F
                  else i_imm args
        safeArgs = args { i_imm = safeImm }
    in packIType 0x13 (getArithFmt op) safeArgs 
assembleSome (SomeInstruction (LoadI op args))   = packIType 0x03 (getLoadFmt op, 0x00) args
assembleSome (SomeInstruction (JumpI JALR args)) = packIType 0x67 (0x0, 0x0) args
assembleSome (SomeInstruction instr@(BType _ _)) = assembleBType instr
assembleSome (SomeInstruction instr@(SType _ _)) = assembleSType instr
assembleSome (SomeInstruction instr@(UType _ _)) = assembleUType instr
assembleSome (SomeInstruction instr@(JType _ _)) = assembleJType instr

assemble :: Program -> [Word32]
assemble = map assembleSome
