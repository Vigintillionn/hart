module ISA where
import Data.Word (Word32)
import Data.List (find)
import Types

class (Enum a, Bounded a, Eq a) => RISCVEncoding a where
    getOpcode :: a -> Word32
    getFunct3 :: a -> Word32
    
    getFunct7 :: a -> Word32
    getFunct7 _ = 0

matchOp :: RISCVEncoding a => Word32 -> Word32 -> Word32 -> Maybe a
matchOp op f3 f7 = find predicate [minBound .. maxBound]
  where
    predicate inst = 
        getOpcode inst == op && 
        getFunct3 inst == f3 && 
        getFunct7 inst == f7

matchOpF3 :: RISCVEncoding a => Word32 -> Word32 -> Maybe a
matchOpF3 op f3 = find predicate [minBound .. maxBound]
  where
    predicate inst = 
        getOpcode inst == op && 
        getFunct3 inst == f3

instance RISCVEncoding ROp where
    getOpcode _ = 0x33
    getFunct3 op = case op of
        ADD -> 0x0; SUB -> 0x0; 
        XOR -> 0x4; OR  -> 0x6; AND -> 0x7
        SLL -> 0x1; SRL -> 0x5; SRA -> 0x5; 
        SLT -> 0x2; SLTU-> 0x3
        MUL -> 0x0; MULH -> 0x1; MULHSU -> 0x2; MULHU -> 0x3
        DIV -> 0x4; DIVU -> 0x5; REM  -> 0x6; REMU  -> 0x7
    getFunct7 op = case op of
        SUB -> 0x20; SRA -> 0x20
        MUL -> 0x01; MULH -> 0x01; MULHSU -> 0x01; MULHU -> 0x01
        DIV -> 0x01; DIVU -> 0x01; REM  -> 0x01; REMU  -> 0x01
        _   -> 0x00

instance RISCVEncoding IArithOp where
    getOpcode _ = 0x13
    getFunct3 op = case op of
        ADDI -> 0x0; XORI -> 0x4; ORI  -> 0x6; ANDI -> 0x7
        SLLI -> 0x1; SRLI -> 0x5; SRAI -> 0x5; 
        SLTI -> 0x2; SLTIU -> 0x3
    getFunct7 op = case op of
        SRAI -> 0x20
        _    -> 0x00 

instance RISCVEncoding ILoadOp where
    getOpcode _ = 0x03
    getFunct3 op = case op of
        LB -> 0x0; LH -> 0x1; LW -> 0x2; 
        LBU -> 0x4; LHU -> 0x5

instance RISCVEncoding BOp where
    getOpcode _ = 0x63
    getFunct3 op = case op of
        BEQ -> 0x0; BNE -> 0x1; BLT -> 0x4; BGE -> 0x5; 
        BLTU -> 0x6; BGEU -> 0x7

instance RISCVEncoding SOp where
    getOpcode _ = 0x23
    getFunct3 op = case op of
        SB -> 0x0; SH -> 0x1; SW -> 0x2

instance RISCVEncoding UOp where
    getOpcode op = case op of 
        AUIPC -> 0x17
        LUI -> 0x37
    getFunct3 _ = 0 -- Unused

instance RISCVEncoding IJmpOp where
    getOpcode _ = 0x67 -- JALR
    getFunct3 _ = 0x0

instance RISCVEncoding JOp where
    getOpcode _ = 0x6F -- JAL
    getFunct3 _ = 0 -- Unused

instance RISCVEncoding SysOp where
    getOpcode _ = 0x73
    getFunct3 op = case op of 
        CSRRW -> 0x1 
        CSRRS -> 0x2 
        CSRRC -> 0x3 

instance RISCVEncoding SysIOp where
    getOpcode _ = 0x73
    getFunct3 op = case op of 
        CSRRWI -> 0x5 
        CSRRSI -> 0x6 
        CSRRCI -> 0x7

instance RISCVEncoding TrapOp where
    getOpcode _ = 0x73
    getFunct3 _ = 0
