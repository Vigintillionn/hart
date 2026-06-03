module Extension.Classify
  ( HasExtension (..),
    instructionExtension,
  )
where

import Extension (Extension (..))
import Types

class HasExtension a where
  extensionOf :: a -> Extension

instance HasExtension ROp where
  extensionOf op = case op of
    -- base integer register-register arithmetic
    ADD -> IExt
    SUB -> IExt
    XOR -> IExt
    OR -> IExt
    AND -> IExt
    SLL -> IExt
    SRL -> IExt
    SRA -> IExt
    SLT -> IExt
    SLTU -> IExt
    -- M: multiply / divide / remainder
    MUL -> MExt
    MULH -> MExt
    MULHSU -> MExt
    MULHU -> MExt
    DIV -> MExt
    DIVU -> MExt
    REM -> MExt
    REMU -> MExt

instance HasExtension IArithOp where
  extensionOf op = case op of
    ADDI -> IExt
    XORI -> IExt
    ORI -> IExt
    ANDI -> IExt
    SLLI -> IExt
    SRLI -> IExt
    SRAI -> IExt
    SLTI -> IExt
    SLTIU -> IExt

instance HasExtension ILoadOp where
  extensionOf op = case op of
    LB -> IExt
    LH -> IExt
    LW -> IExt
    LBU -> IExt
    LHU -> IExt

instance HasExtension IJmpOp where
  extensionOf JALR = IExt

instance HasExtension BOp where
  extensionOf op = case op of
    BEQ -> IExt
    BNE -> IExt
    BLT -> IExt
    BGE -> IExt
    BLTU -> IExt
    BGEU -> IExt

instance HasExtension SOp where
  extensionOf op = case op of
    SB -> IExt
    SH -> IExt
    SW -> IExt

instance HasExtension UOp where
  extensionOf op = case op of
    LUI -> IExt
    AUIPC -> IExt

instance HasExtension JOp where
  extensionOf JAL = IExt

instance HasExtension SysOp where
  extensionOf op = case op of
    CSRRW -> IExt
    CSRRS -> IExt
    CSRRC -> IExt

instance HasExtension SysIOp where
  extensionOf op = case op of
    CSRRWI -> IExt
    CSRRSI -> IExt
    CSRRCI -> IExt

instance HasExtension TrapOp where
  extensionOf op = case op of
    ECALL -> IExt
    EBREAK -> IExt

-- | Which extension an already-decoded instruction belongs to.
instructionExtension :: SomeInstruction a -> Extension
instructionExtension (SomeInstruction i) = case i of
  RType op _ -> extensionOf op
  ArithI op _ -> extensionOf op
  LoadI op _ -> extensionOf op
  JumpI op _ -> extensionOf op
  BType op _ -> extensionOf op
  SType op _ -> extensionOf op
  UType op _ -> extensionOf op
  JType op _ -> extensionOf op
  System op _ -> extensionOf op
  SystemI op _ -> extensionOf op
  Trap op -> extensionOf op
