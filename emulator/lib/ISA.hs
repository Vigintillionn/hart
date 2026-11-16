module ISA (RISCVEncoding (..), matchOp, matchOpF3, getFunct12, matchUnary) where

import Data.Bits (shiftR)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Word (Word32)
import Types

class (Enum a, Bounded a, Eq a) => RISCVEncoding a where
  getOpcode :: a -> Word32
  getFunct3 :: a -> Word32

  getFunct7 :: a -> Word32
  getFunct7 _ = 0

  opTableF3 :: Map (Word32, Word32) a
  opTableF3 = Map.fromList [((getOpcode x, getFunct3 x), x) | x <- [minBound .. maxBound]]

  opTableF7 :: Map (Word32, Word32, Word32) a
  opTableF7 = Map.fromList [((getOpcode x, getFunct3 x, getFunct7 x), x) | x <- [minBound .. maxBound]]

matchOp :: (RISCVEncoding a) => Word32 -> Word32 -> Word32 -> Maybe a
matchOp op f3 f7 = Map.lookup (op, f3, f7) opTableF7

matchOpF3 :: (RISCVEncoding a) => Word32 -> Word32 -> Maybe a
matchOpF3 op f3 = Map.lookup (op, f3) opTableF3

instance RISCVEncoding ROp where
  getOpcode _ = 0x33
  getFunct3 op = case op of
    ADD -> 0x0
    SUB -> 0x0
    XOR -> 0x4
    OR -> 0x6
    AND -> 0x7
    SLL -> 0x1
    SRL -> 0x5
    SRA -> 0x5
    SLT -> 0x2
    SLTU -> 0x3
    MUL -> 0x0
    MULH -> 0x1
    MULHSU -> 0x2
    MULHU -> 0x3
    DIV -> 0x4
    DIVU -> 0x5
    REM -> 0x6
    REMU -> 0x7
    CZERO_EQZ -> 0x5
    CZERO_NEZ -> 0x7
    SH1ADD -> 0x2
    SH2ADD -> 0x4
    SH3ADD -> 0x6
    ANDN -> 0x7
    ORN -> 0x6
    XNOR -> 0x4
    MAX -> 0x6
    MAXU -> 0x7
    MIN -> 0x4
    MINU -> 0x5
    ROL -> 0x1
    ROR -> 0x5
    BCLR -> 0x1
    BEXT -> 0x5
    BINV -> 0x1
    BSET -> 0x1
  getFunct7 op = case op of
    SUB -> 0x20
    SRA -> 0x20
    MUL -> 0x01
    MULH -> 0x01
    MULHSU -> 0x01
    MULHU -> 0x01
    DIV -> 0x01
    DIVU -> 0x01
    REM -> 0x01
    REMU -> 0x01
    CZERO_EQZ -> 0x07
    CZERO_NEZ -> 0x07
    SH1ADD -> 0x10
    SH2ADD -> 0x10
    SH3ADD -> 0x10
    ANDN -> 0x20
    ORN -> 0x20
    XNOR -> 0x20
    MAX -> 0x05
    MAXU -> 0x05
    MIN -> 0x05
    MINU -> 0x05
    ROL -> 0x30
    ROR -> 0x30
    BCLR -> 0x24
    BEXT -> 0x24
    BINV -> 0x34
    BSET -> 0x14
    _ -> 0x00

instance RISCVEncoding IArithOp where
  getOpcode _ = 0x13
  getFunct3 op = case op of
    ADDI -> 0x0
    XORI -> 0x4
    ORI -> 0x6
    ANDI -> 0x7
    SLLI -> 0x1
    SRLI -> 0x5
    SRAI -> 0x5
    SLTI -> 0x2
    SLTIU -> 0x3
    RORI -> 0x5
    BCLRI -> 0x1
    BEXTI -> 0x5
    BINVI -> 0x1
    BSETI -> 0x1
  getFunct7 op = case op of
    SRAI -> 0x20
    RORI -> 0x30
    BCLRI -> 0x24
    BEXTI -> 0x24
    BINVI -> 0x34
    BSETI -> 0x14
    _ -> 0x00

instance RISCVEncoding UnaryOp where
  getOpcode op = case op of
    ZEXT_H -> 0x33
    _ -> 0x13
  getFunct3 op = case op of
    CLZ -> 0x1
    CTZ -> 0x1
    CPOP -> 0x1
    SEXT_B -> 0x1
    SEXT_H -> 0x1
    ZEXT_H -> 0x4
    ORC_B -> 0x5
    REV8 -> 0x5
  getFunct7 op = getFunct12 op `shiftR` 5

-- | Unary ops fix the whole immediate field, so funct7 alone can't tell them
-- apart (clz, ctz and cpop differ only in the rs2 bits).
getFunct12 :: UnaryOp -> Word32
getFunct12 op = case op of
  CLZ -> 0x600
  CTZ -> 0x601
  CPOP -> 0x602
  SEXT_B -> 0x604
  SEXT_H -> 0x605
  ZEXT_H -> 0x080
  ORC_B -> 0x287
  REV8 -> 0x698

unaryTable :: Map (Word32, Word32, Word32) UnaryOp
unaryTable = Map.fromList [((getOpcode x, getFunct3 x, getFunct12 x), x) | x <- [minBound .. maxBound]]

matchUnary :: Word32 -> Word32 -> Word32 -> Maybe UnaryOp
matchUnary op f3 f12 = Map.lookup (op, f3, f12) unaryTable

instance RISCVEncoding ILoadOp where
  getOpcode _ = 0x03
  getFunct3 op = case op of
    LB -> 0x0
    LH -> 0x1
    LW -> 0x2
    LBU -> 0x4
    LHU -> 0x5

instance RISCVEncoding BOp where
  getOpcode _ = 0x63
  getFunct3 op = case op of
    BEQ -> 0x0
    BNE -> 0x1
    BLT -> 0x4
    BGE -> 0x5
    BLTU -> 0x6
    BGEU -> 0x7

instance RISCVEncoding SOp where
  getOpcode _ = 0x23
  getFunct3 op = case op of
    SB -> 0x0
    SH -> 0x1
    SW -> 0x2

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
