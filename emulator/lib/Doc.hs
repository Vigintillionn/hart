{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Doc
  ( FormatKind (..),
    OperandDoc (..),
    FieldDoc (..),
    FormatInfo (..),
    OpDoc (..),
    formatInfo,
    formatCatalogue,
    InstructionInfo (..),
    instructionCatalogue,
    PseudoInfo (..),
    pseudoCatalogue,
    SyscallDoc (..),
    SyscallInfo (..),
    RegisterUse (..),
    syscallCatalogue,
    DirectiveInfo (..),
    directiveCatalogue,
    CsrInfo (..),
    csrCatalogue,
  )
where

import Data.Aeson (ToJSON (..), object, (.=))
import Data.Char (toLower)
import Data.Word (Word32)
import Extension (extensionCode)
import Extension.Classify (HasExtension (..))
import Kernel (Syscall (..), syscallCode)
import Numeric (showHex)
import Types

-- | The instruction formats, in display order
data FormatKind
  = FmtR
  | FmtI
  | FmtShift
  | FmtLoad
  | FmtS
  | FmtB
  | FmtU
  | FmtJ
  | FmtJalr
  | FmtCsr
  | FmtCsrI
  | FmtTrap
  deriving (Show, Eq, Enum, Bounded)

data OperandDoc = OperandDoc {opToken :: String, opDesc :: String}
  deriving (Show, Eq)

data FieldDoc = FieldDoc
  { fldName :: String,
    fldHi :: Int,
    fldLo :: Int,
    fldRole :: String
  }
  deriving (Show, Eq)

data FormatInfo = FormatInfo
  { fmtId :: String,
    fmtName :: String,
    fmtKind :: String,
    fmtSyntax :: String,
    fmtOperands :: [OperandDoc],
    fmtFields :: [FieldDoc],
    fmtBlurb :: String
  }
  deriving (Show, Eq)

opcodeF :: FieldDoc
opcodeF = FieldDoc "opcode" 6 0 "opcode"

regF :: String -> Int -> FieldDoc
regF name hi = FieldDoc name hi (hi - 4) "reg"

functF :: String -> Int -> Int -> FieldDoc
functF name hi lo = FieldDoc name hi lo "funct"

immF :: String -> Int -> Int -> FieldDoc
immF name hi lo = FieldDoc name hi lo "imm"

formatInfo :: FormatKind -> FormatInfo
formatInfo FmtR =
  FormatInfo
    "r"
    "R-type"
    "Register-register"
    "rd, rs1, rs2"
    [ OperandDoc "rd" "destination register",
      OperandDoc "rs1" "first source register",
      OperandDoc "rs2" "second source register"
    ]
    [ functF "funct7" 31 25,
      regF "rs2" 24,
      regF "rs1" 19,
      functF "funct3" 14 12,
      regF "rd" 11,
      opcodeF
    ]
    "Operate on two source registers and write the result to rd. No immediate is encoded, so the operands are always three registers."
formatInfo FmtI =
  FormatInfo
    "i"
    "I-type"
    "Register-immediate"
    "rd, rs1, imm"
    [ OperandDoc "rd" "destination register",
      OperandDoc "rs1" "source register",
      OperandDoc "imm" "12-bit signed immediate (-2048…2047)"
    ]
    [ immF "imm[11:0]" 31 20,
      regF "rs1" 19,
      functF "funct3" 14 12,
      regF "rd" 11,
      opcodeF
    ]
    "Combine a register with a sign-extended 12-bit immediate and write rd."
formatInfo FmtShift =
  FormatInfo
    "shift"
    "I-type (shift)"
    "Immediate shift"
    "rd, rs1, shamt"
    [ OperandDoc "rd" "destination register",
      OperandDoc "rs1" "source register",
      OperandDoc "shamt" "shift amount, 0…31 (5 bits)"
    ]
    [ functF "funct7" 31 25,
      immF "shamt" 24 20,
      regF "rs1" 19,
      functF "funct3" 14 12,
      regF "rd" 11,
      opcodeF
    ]
    "Shift rs1 by a constant amount held in the immediate field. Only the low 5 bits are meaningful, so the shift is always 0-31."
formatInfo FmtLoad =
  FormatInfo
    "load"
    "I-type (load)"
    "Memory load"
    "rd, imm(rs1)"
    [ OperandDoc "rd" "destination register",
      OperandDoc "imm" "12-bit signed byte offset",
      OperandDoc "rs1" "base address register"
    ]
    [ immF "imm[11:0]" 31 20,
      regF "rs1" 19,
      functF "funct3" 14 12,
      regF "rd" 11,
      opcodeF
    ]
    "Read from memory at address rs1 + imm into rd. The access width and whether the value is sign- or zero-extended depend on the mnemonic."
formatInfo FmtS =
  FormatInfo
    "s"
    "S-type"
    "Memory store"
    "rs2, imm(rs1)"
    [ OperandDoc "rs2" "register holding the value to store",
      OperandDoc "imm" "12-bit signed byte offset",
      OperandDoc "rs1" "base address register"
    ]
    [ immF "imm[11:5]" 31 25,
      regF "rs2" 24,
      regF "rs1" 19,
      functF "funct3" 14 12,
      immF "imm[4:0]" 11 7,
      opcodeF
    ]
    "Write rs2 to memory at address rs1 + imm. There is no destination register, so stores never change the register file."
formatInfo FmtB =
  FormatInfo
    "b"
    "B-type"
    "Conditional branch"
    "rs1, rs2, label"
    [ OperandDoc "rs1" "first register compared",
      OperandDoc "rs2" "second register compared",
      OperandDoc "label" "branch target (PC-relative)"
    ]
    [ immF "imm[12]" 31 31,
      immF "imm[10:5]" 30 25,
      regF "rs2" 24,
      regF "rs1" 19,
      functF "funct3" 14 12,
      immF "imm[4:1]" 11 8,
      immF "imm[11]" 7 7,
      opcodeF
    ]
    "Compare two registers and, if the condition holds, branch to label; otherwise fall through to the next instruction. The target is encoded as a signed PC-relative offset."
formatInfo FmtU =
  FormatInfo
    "u"
    "U-type"
    "Upper immediate"
    "rd, imm"
    [ OperandDoc "rd" "destination register",
      OperandDoc "imm" "20-bit immediate (forms the upper bits)"
    ]
    [ immF "imm[31:12]" 31 12,
      regF "rd" 11,
      opcodeF
    ]
    "Place a 20-bit immediate in the upper bits of rd with the low 12 bits zeroed. Paired with an addi, this is how any 32-bit constant or address is constructed."
formatInfo FmtJ =
  FormatInfo
    "j"
    "J-type"
    "Unconditional jump"
    "rd, label"
    [ OperandDoc "rd" "register to receive the return address",
      OperandDoc "label" "jump target (PC-relative)"
    ]
    [ immF "imm[20]" 31 31,
      immF "imm[10:1]" 30 21,
      immF "imm[11]" 20 20,
      immF "imm[19:12]" 19 12,
      regF "rd" 11,
      opcodeF
    ]
    "Jump to label and save the return address (pc + 4) in rd. Using rd = ra makes it a call; using rd = zero makes it a plain jump."
formatInfo FmtJalr =
  FormatInfo
    "jalr"
    "I-type (jump)"
    "Indirect jump"
    "rd, rs1, imm"
    [ OperandDoc "rd" "register to receive the return address",
      OperandDoc "rs1" "base address register",
      OperandDoc "imm" "12-bit signed offset"
    ]
    [ immF "imm[11:0]" 31 20,
      regF "rs1" 19,
      functF "funct3" 14 12,
      regF "rd" 11,
      opcodeF
    ]
    "Jump to a computed address (rs1 + imm) with the low bit forced to 0, saving pc + 4 in rd. It is the building block for returns and indirect calls."
formatInfo FmtCsr =
  FormatInfo
    "csr"
    "System (CSR)"
    "Control/status register"
    "rd, csr, rs1"
    [ OperandDoc "rd" "register to receive the old CSR value",
      OperandDoc "csr" "control/status register name or address",
      OperandDoc "rs1" "source register"
    ]
    [ immF "csr" 31 20,
      regF "rs1" 19,
      functF "funct3" 14 12,
      regF "rd" 11,
      opcodeF
    ]
    "Atomically read a control/status register into rd and update it from rs1. The three variants write, set, or clear bits."
formatInfo FmtCsrI =
  FormatInfo
    "csri"
    "System (CSR imm)"
    "Control/status register"
    "rd, csr, uimm"
    [ OperandDoc "rd" "register to receive the old CSR value",
      OperandDoc "csr" "control/status register name or address",
      OperandDoc "uimm" "5-bit zero-extended immediate (0…31)"
    ]
    [ immF "csr" 31 20,
      immF "uimm" 19 15,
      functF "funct3" 14 12,
      regF "rd" 11,
      opcodeF
    ]
    "Like the register CSR instructions, but the operand is a 5-bit immediate instead of a register; handy for setting or clearing a few known bits."
formatInfo FmtTrap =
  FormatInfo
    "trap"
    "System (trap)"
    "Environment"
    ""
    []
    [ functF "funct12" 31 20,
      FieldDoc "0" 19 7 "zero",
      opcodeF
    ]
    "Raise a synchronous trap to the execution environment. These take no operands."

formatCatalogue :: [FormatInfo]
formatCatalogue = map formatInfo [minBound .. maxBound]

-- | Per-opcode documentation. The mnemonic defaults to the (lower-cased)
-- constructor name
class (Show a) => OpDoc a where
  opFormat :: a -> FormatKind
  opOperation :: a -> String
  opDescription :: a -> String
  opMnemonic :: a -> String
  opMnemonic = map toLower . show

-- Useful UNICODE symbols for documentation
-- ᵤ = unsigned, ₛ = signed, × = multiply, ÷, % = remainder, … = range, != = not equal
-- >= = greater or equal, <= = less or equal, → = arrow

instance OpDoc ROp where
  opFormat _ = FmtR
  opOperation op = case op of
    ADD -> "rd = rs1 + rs2"
    SUB -> "rd = rs1 - rs2"
    XOR -> "rd = rs1 ^ rs2"
    OR -> "rd = rs1 | rs2"
    AND -> "rd = rs1 & rs2"
    SLL -> "rd = rs1 << rs2"
    SRL -> "rd = rs1 >>ᵤ rs2"
    SRA -> "rd = rs1 >>ₛ rs2"
    SLT -> "rd = rs1 < rs2"
    SLTU -> "rd = rs1 <ᵤ rs2"
    MUL -> "rd = (rs1 × rs2)[31:0]"
    MULH -> "rd = (rs1 × rs2)[63:32]"
    MULHSU -> "rd = (rs1ₛ × rs2ᵤ)[63:32]"
    MULHU -> "rd = (rs1 × rs2)[63:32]"
    DIV -> "rd = rs1 ÷ rs2"
    DIVU -> "rd = rs1 ÷ᵤ rs2"
    REM -> "rd = rs1 % rs2"
    REMU -> "rd = rs1 %ᵤ rs2"
  opDescription op = case op of
    ADD -> "Adds the two source registers and writes the sum to rd. Overflow wraps around modulo 2³² and is not flagged."
    SUB -> "Subtracts rs2 from rs1. Like add, any overflow wraps silently."
    XOR -> "Bitwise exclusive-OR of the two registers."
    OR -> "Bitwise OR of the two registers."
    AND -> "Bitwise AND of the two registers: commonly used to mask off bits."
    SLL -> "Logical left shift of rs1 by the low 5 bits of rs2, shifting in zeros."
    SRL -> "Logical right shift of rs1 by the low 5 bits of rs2, shifting in zeros."
    SRA -> "Arithmetic right shift by the low 5 bits of rs2; the sign bit is replicated so the sign is preserved."
    SLT -> "Set-less-than: writes 1 to rd when rs1 is less than rs2 (signed), otherwise 0."
    SLTU -> "Set-less-than unsigned: writes 1 when rs1 < rs2 treating both as unsigned, otherwise 0."
    MUL -> "Writes the lower 32 bits of the product. The signedness of the operands doesn't affect the low word."
    MULH -> "Upper 32 bits of the full 64-bit product, treating both operands as signed."
    MULHSU -> "Upper 32 bits of the product with rs1 signed and rs2 unsigned."
    MULHU -> "Upper 32 bits of the product, treating both operands as unsigned."
    DIV -> "Signed division truncated toward zero. Dividing by zero yields -1; the INT_MIN ÷ -1 overflow yields INT_MIN."
    DIVU -> "Unsigned division. Dividing by zero yields the all-ones value (2³²-1)."
    REM -> "Signed remainder; the result takes the sign of the dividend. Remainder by zero yields rs1 unchanged."
    REMU -> "Unsigned remainder. Remainder by zero yields rs1 unchanged."

instance OpDoc IArithOp where
  opFormat op = case op of
    SLLI -> FmtShift
    SRLI -> FmtShift
    SRAI -> FmtShift
    _ -> FmtI
  opOperation op = case op of
    ADDI -> "rd = rs1 + imm"
    XORI -> "rd = rs1 ^ imm"
    ORI -> "rd = rs1 | imm"
    ANDI -> "rd = rs1 & imm"
    SLTI -> "rd = rs1 < imm"
    SLTIU -> "rd = rs1 <ᵤ imm"
    SLLI -> "rd = rs1 << shamt"
    SRLI -> "rd = rs1 >>ᵤ shamt"
    SRAI -> "rd = rs1 >>ₛ shamt"
  opDescription op = case op of
    ADDI -> "Adds a sign-extended 12-bit immediate to rs1."
    XORI -> "Bitwise XOR with a sign-extended immediate."
    ORI -> "Bitwise OR with a sign-extended immediate."
    ANDI -> "Bitwise AND with a sign-extended immediate; typically used to keep only the low bits of a value."
    SLTI -> "Writes 1 to rd when rs1 is less than the signed immediate, otherwise 0."
    SLTIU -> "Unsigned compare against the immediate (sign-extended, then read as unsigned)."
    SLLI -> "Logical left shift by a constant 0-31, shifting in zeros."
    SRLI -> "Logical right shift by a constant, shifting in zeros."
    SRAI -> "Arithmetic right shift by a constant; the sign bit is replicated."

instance OpDoc ILoadOp where
  opFormat _ = FmtLoad
  opOperation op = case op of
    LB -> "rd = sext(mem8)"
    LH -> "rd = sext(mem16)"
    LW -> "rd = mem32"
    LBU -> "rd = zext(mem8)"
    LHU -> "rd = zext(mem16)"
  opDescription op = case op of
    LB -> "Loads one byte from rs1 + imm and sign-extends it to 32 bits."
    LH -> "Loads a 16-bit halfword from rs1 + imm and sign-extends it to 32 bits."
    LW -> "Loads a full 32-bit word from rs1 + imm into rd."
    LBU -> "Loads one byte and zero-extends it, giving a value in 0…255."
    LHU -> "Loads a 16-bit halfword and zero-extends it, giving a value in 0…65535."

instance OpDoc IJmpOp where
  opFormat _ = FmtJalr
  opOperation JALR = "rd = pc+4; pc = (rs1+imm)&~1"
  opDescription JALR = "Jump And Link Register: jumps to the computed address rs1 + imm (low bit cleared) and saves pc + 4 in rd. Used for ret and indirect calls."

instance OpDoc BOp where
  opFormat _ = FmtB
  opOperation op = case op of
    BEQ -> "if rs1 == rs2 → label"
    BNE -> "if rs1 != rs2 → label"
    BLT -> "if rs1 < rs2 → label"
    BGE -> "if rs1 >= rs2 → label"
    BLTU -> "if rs1 <ᵤ rs2 → label"
    BGEU -> "if rs1 >=ᵤ rs2 → label"
  opDescription op = case op of
    BEQ -> "Branches to label when the two registers are equal."
    BNE -> "Branches to label when the two registers differ."
    BLT -> "Signed less-than branch."
    BGE -> "Signed greater-or-equal branch."
    BLTU -> "Unsigned less-than branch."
    BGEU -> "Unsigned greater-or-equal branch."

instance OpDoc SOp where
  opFormat _ = FmtS
  opOperation op = case op of
    SB -> "mem8 = rs2[7:0]"
    SH -> "mem16 = rs2[15:0]"
    SW -> "mem32 = rs2"
  opDescription op = case op of
    SB -> "Stores the low byte of rs2 to memory at rs1 + imm."
    SH -> "Stores the low 16 bits of rs2 to memory at rs1 + imm."
    SW -> "Stores the full 32-bit word in rs2 to memory at rs1 + imm."

instance OpDoc UOp where
  opFormat _ = FmtU
  opOperation op = case op of
    LUI -> "rd = imm << 12"
    AUIPC -> "rd = pc + (imm << 12)"
  opDescription op = case op of
    LUI -> "Load Upper Immediate: puts a 20-bit constant in the top bits of rd with the low 12 bits zero. Combined with addi it builds any 32-bit value."
    AUIPC -> "Add Upper Immediate to PC: forms a PC-relative address. Paired with addi or jalr it underpins position-independent code (la, call)."

instance OpDoc JOp where
  opFormat _ = FmtJ
  opOperation JAL = "rd = pc+4; pc += imm"
  opDescription JAL = "Jump And Link: saves the return address in rd and jumps to label. With rd = ra it is a function call; with rd = zero it is a plain jump."

instance OpDoc SysOp where
  opFormat _ = FmtCsr
  opOperation op = case op of
    CSRRW -> "rd = csr; csr = rs1"
    CSRRS -> "rd = csr; csr |= rs1"
    CSRRC -> "rd = csr; csr &= ~rs1"
  opDescription op = case op of
    CSRRW -> "Atomically reads the CSR into rd, then writes rs1 into it."
    CSRRS -> "Reads the CSR into rd, then sets every bit that is 1 in rs1. With rs1 = zero it is a pure read."
    CSRRC -> "Reads the CSR into rd, then clears every bit that is 1 in rs1."

instance OpDoc SysIOp where
  opFormat _ = FmtCsrI
  opOperation op = case op of
    CSRRWI -> "rd = csr; csr = uimm"
    CSRRSI -> "rd = csr; csr |= uimm"
    CSRRCI -> "rd = csr; csr &= ~uimm"
  opDescription op = case op of
    CSRRWI -> "Like csrrw, but the new value comes from a 5-bit immediate (0…31)."
    CSRRSI -> "Reads the CSR, then sets the bits selected by the 5-bit immediate."
    CSRRCI -> "Reads the CSR, then clears the bits selected by the 5-bit immediate."

instance OpDoc TrapOp where
  opFormat _ = FmtTrap
  opOperation op = case op of
    ECALL -> "trap → environment"
    EBREAK -> "trap → debugger"
  opDescription op = case op of
    ECALL -> "Environment call: requests a service from the runtime. The emulator dispatches on the syscall number in a7 (print/read, sbrk, file ops, exit)."
    EBREAK -> "Raises a breakpoint exception, handing control back to the debugger so you can inspect machine state."

data InstructionInfo = InstructionInfo
  { insnMnemonic :: String,
    insnExtension :: String,
    insnFormat :: String,
    insnOperation :: String,
    insnDescription :: String
  }
  deriving (Show, Eq)

docsFor :: forall a. (OpDoc a, HasExtension a, Enum a, Bounded a) => [InstructionInfo]
docsFor = [toInfo x | x <- [minBound .. maxBound :: a]]
  where
    toInfo x =
      InstructionInfo
        { insnMnemonic = opMnemonic x,
          insnExtension = extensionCode (extensionOf x),
          insnFormat = fmtId (formatInfo (opFormat x)),
          insnOperation = opOperation x,
          insnDescription = opDescription x
        }

instructionCatalogue :: [InstructionInfo]
instructionCatalogue =
  concat
    [ docsFor @ROp,
      docsFor @IArithOp,
      docsFor @ILoadOp,
      docsFor @IJmpOp,
      docsFor @BOp,
      docsFor @SOp,
      docsFor @UOp,
      docsFor @JOp,
      docsFor @SysOp,
      docsFor @SysIOp,
      docsFor @TrapOp
    ]

data PseudoInfo = PseudoInfo
  { pseudoMnemonic :: String,
    pseudoExtension :: String,
    pseudoSyntax :: String,
    pseudoExpands :: String,
    pseudoDescription :: String
  }
  deriving (Show, Eq)

pseudoCatalogue :: [PseudoInfo]
pseudoCatalogue =
  map
    base
    [ ("nop", "", "addi zero, zero, 0", "No operation; advances the PC and changes nothing."),
      ("mv", "rd, rs", "addi rd, rs, 0", "Copies the value in rs into rd."),
      ("li", "rd, imm", "lui (+ addi)", "Load Immediate: loads any 32-bit constant, emitting one or two instructions as needed."),
      ("la", "rd, symbol", "auipc + addi", "Load Address: puts the (PC-relative) address of a label into rd."),
      ("neg", "rd, rs", "sub rd, zero, rs", "Two's-complement negation (rd = -rs)."),
      ("not", "rd, rs", "xori rd, rs, -1", "Bitwise NOT (one's complement) of rs."),
      ("seqz", "rd, rs", "sltiu rd, rs, 1", "Set if equal to zero: rd = 1 when rs == 0, else 0."),
      ("snez", "rd, rs", "sltu rd, zero, rs", "Set if not zero: rd = 1 when rs ≠ 0, else 0."),
      ("sltz", "rd, rs", "slt rd, rs, zero", "Set if less than zero: rd = 1 when rs < 0, else 0."),
      ("sgtz", "rd, rs", "slt rd, zero, rs", "Set if greater than zero: rd = 1 when rs > 0, else 0."),
      ("j", "label", "jal zero, label", "Unconditional jump; the return address is discarded."),
      ("jr", "rs", "jalr zero, rs, 0", "Jump to the address held in a register."),
      ("ret", "", "jalr zero, ra, 0", "Return from a function by jumping to the address in ra."),
      ("call", "symbol", "auipc + jalr", "Call a function that may be far away, saving the return address in ra."),
      ("tail", "symbol", "auipc + jalr", "Tail-call a function; jumps without saving a return address."),
      ("beqz", "rs, label", "beq rs, zero, label", "Branch when rs == 0."),
      ("bnez", "rs, label", "bne rs, zero, label", "Branch when rs ≠ 0."),
      ("blez", "rs, label", "bge zero, rs, label", "Branch when rs ≤ 0 (signed)."),
      ("bgez", "rs, label", "bge rs, zero, label", "Branch when rs ≥ 0 (signed)."),
      ("bltz", "rs, label", "blt rs, zero, label", "Branch when rs < 0 (signed)."),
      ("bgtz", "rs, label", "blt zero, rs, label", "Branch when rs > 0 (signed)."),
      ("bgt", "rs, rt, label", "blt rt, rs, label", "Branch when rs > rt (signed); the operands are swapped to reuse blt."),
      ("ble", "rs, rt, label", "bge rt, rs, label", "Branch when rs ≤ rt (signed)."),
      ("bgtu", "rs, rt, label", "bltu rt, rs, label", "Branch when rs > rt (unsigned)."),
      ("bleu", "rs, rt, label", "bgeu rt, rs, label", "Branch when rs ≤ rt (unsigned)."),
      ("lw", "rd, symbol", "auipc + lw", "Loads a word from a labelled global into rd."),
      ("sw", "rd, symbol, rt", "auipc + sw", "Stores rd to a labelled global, using rt as a scratch register for the address.")
    ]
    ++ map
      zicsr
      [ ("csrr", "rd, csr", "csrrs rd, csr, zero", "Read a CSR into rd, without writing it back."),
        ("csrw", "csr, rs", "csrrw zero, csr, rs", "Write rs into a CSR, discarding the old value."),
        ("csrs", "csr, rs", "csrrs zero, csr, rs", "Set in a CSR the bits that are set in rs."),
        ("csrc", "csr, rs", "csrrc zero, csr, rs", "Clear in a CSR the bits that are set in rs."),
        ("csrwi", "csr, uimm", "csrrwi zero, csr, uimm", "Write a 5-bit immediate into a CSR."),
        ("csrsi", "csr, uimm", "csrrsi zero, csr, uimm", "Set in a CSR the bits named by a 5-bit immediate."),
        ("csrci", "csr, uimm", "csrrci zero, csr, uimm", "Clear in a CSR the bits named by a 5-bit immediate.")
      ]
  where
    base (m, s, e, d) = PseudoInfo m "I" s e d
    zicsr (m, s, e, d) = PseudoInfo m "Zicsr" s e d

instance ToJSON OperandDoc where
  toJSON (OperandDoc token desc) = object ["token" .= token, "desc" .= desc]

instance ToJSON FieldDoc where
  toJSON (FieldDoc name hi lo role) =
    object
      [ "name" .= name,
        "hi" .= hi,
        "lo" .= lo,
        "role" .= role
      ]

instance ToJSON FormatInfo where
  toJSON (FormatInfo fid name kind syntax operands fields blurb) =
    object
      [ "id" .= fid,
        "name" .= name,
        "kind" .= kind,
        "syntax" .= syntax,
        "operands" .= operands,
        "fields" .= fields,
        "blurb" .= blurb
      ]

instance ToJSON InstructionInfo where
  toJSON (InstructionInfo mnemonic ext fmt operation desc) =
    object
      [ "mnemonic" .= mnemonic,
        "extension" .= ext,
        "format" .= fmt,
        "operation" .= operation,
        "description" .= desc
      ]

instance ToJSON PseudoInfo where
  toJSON (PseudoInfo mnemonic ext syntax expands desc) =
    object
      [ "mnemonic" .= mnemonic,
        "extension" .= ext,
        "syntax" .= syntax,
        "expands" .= expands,
        "description" .= desc
      ]

data RegisterUse
  = InputRegister String String
  | OutputRegister String String
  deriving (Show, Eq)

class SyscallDoc a where
  syscallName :: a -> String
  syscallRegisters :: a -> [RegisterUse]
  syscallDescription :: a -> String

instance SyscallDoc Syscall where
  syscallName s = case s of
    PrintInt -> "print_int"
    PrintString -> "print_string"
    ReadInt -> "read_int"
    ReadString -> "read_string"
    Exit -> "exit"
    PrintChar -> "print_char"
    OpenAt -> "openat"
    Close -> "close"
    Read -> "read"
    Write -> "write"
    SysExit -> "exit"
    Brk -> "brk"
  syscallRegisters s = case s of
    PrintInt -> [InputRegister "a0" "integer"]
    PrintString -> [InputRegister "a0" "string ptr"]
    ReadInt -> [OutputRegister "a0" "integer"]
    ReadString -> [InputRegister "a0" "buf ptr", InputRegister "a1" "max len"]
    Exit -> []
    PrintChar -> [InputRegister "a0" "char"]
    OpenAt -> [InputRegister "a1" "path ptr", InputRegister "a2" "flags", OutputRegister "a0" "fd"]
    Close -> [InputRegister "a0" "fd", OutputRegister "a0" "status"]
    Read -> [InputRegister "a0" "fd", InputRegister "a1" "buf ptr", InputRegister "a2" "len", OutputRegister "a0" "bytes read"]
    Write -> [InputRegister "a0" "fd", InputRegister "a1" "buf ptr", InputRegister "a2" "len", OutputRegister "a0" "bytes written"]
    SysExit -> [InputRegister "a0" "exit code"]
    Brk -> [InputRegister "a0" "new break", OutputRegister "a0" "break"]
  syscallDescription s = case s of
    PrintInt -> "Prints the signed 32-bit integer held in a0 to the console."
    PrintString -> "Prints the NUL-terminated string pointed to by a0."
    ReadInt -> "Reads a line of input and parses it as a signed integer, returned in a0."
    ReadString -> "Reads a line into the buffer at a0, writing at most a1-1 bytes followed by a NUL terminator."
    Exit -> "Terminates the program normally."
    PrintChar -> "Prints the low byte of a0 as a single ASCII character."
    OpenAt -> "Opens the host file named by the string at a1 (flags: 0 read, 1 write, 2 read/write) and returns its file descriptor in a0."
    Close -> "Closes the open file descriptor in a0, returning a status in a0."
    Read -> "Reads up to a2 bytes from descriptor a0 into the buffer at a1; fd 0 reads from console input. Returns the byte count in a0."
    Write -> "Writes a2 bytes from the buffer at a1 to descriptor a0; fd 1 and 2 write to the console. Returns the byte count in a0."
    SysExit -> "Terminates the program with the exit status in the low 8 bits of a0."
    Brk -> "Moves the program break (heap end) to a0, or queries it when a0 is 0. Returns the resulting break in a0."

data SyscallInfo = SyscallInfo
  { syscallInfoName :: String,
    syscallInfoCode :: Word32,
    syscallInfoRegisters :: [RegisterUse],
    syscallInfoDescription :: String
  }
  deriving (Show, Eq)

syscallCatalogue :: [SyscallInfo]
syscallCatalogue =
  [ SyscallInfo (syscallName s) (syscallCode s) (syscallRegisters s) (syscallDescription s)
    | s <- [minBound .. maxBound]
  ]

instance ToJSON RegisterUse where
  toJSON (InputRegister reg desc) =
    object ["dir" .= ("in" :: String), "reg" .= reg, "desc" .= desc]
  toJSON (OutputRegister reg desc) =
    object ["dir" .= ("out" :: String), "reg" .= reg, "desc" .= desc]

instance ToJSON SyscallInfo where
  toJSON (SyscallInfo name code registers desc) =
    object
      [ "name" .= name,
        "code" .= code,
        "registers" .= registers,
        "description" .= desc
      ]

data DirectiveInfo = DirectiveInfo
  { dirName :: String,
    dirArgs :: String,
    dirDescription :: String
  }
  deriving (Show, Eq)

directiveCatalogue :: [DirectiveInfo]
directiveCatalogue =
  [ DirectiveInfo ".text" "" "Switch to the text section, where instructions are assembled (base address 0x0).",
    DirectiveInfo ".data" "" "Switch to the data section, where initialised data is placed (base address 0x10000000).",
    DirectiveInfo ".bss" "" "Switch to the bss section, for zero-initialised data.",
    DirectiveInfo ".string" "\"…\"" "Emit the string followed by a NUL terminator. .asciz is an alias.",
    DirectiveInfo ".ascii" "\"…\"" "Emit the string bytes without a trailing NUL.",
    DirectiveInfo ".byte" "v, …" "Emit one or more 8-bit values.",
    DirectiveInfo ".half" "v, …" "Emit one or more 16-bit values (little-endian). .short is an alias.",
    DirectiveInfo ".word" "v, …" "Emit one or more 32-bit values (little-endian).",
    DirectiveInfo ".space" "n" "Reserve n zero-filled bytes. .zero is an alias.",
    DirectiveInfo ".align" "n" "Pad with zero bytes until the location counter is a multiple of 2^n."
  ]

instance ToJSON DirectiveInfo where
  toJSON (DirectiveInfo name args desc) =
    object
      [ "name" .= name,
        "args" .= args,
        "description" .= desc
      ]

data CsrInfo = CsrInfo
  { csrInfoName :: String,
    csrInfoAddr :: String,
    csrInfoDescription :: String
  }
  deriving (Show, Eq)

csrDescription :: CSRName -> String
csrDescription c = case c of
  MSTATUS -> "Machine status: global interrupt-enable and prior-state bits."
  MISA -> "Machine ISA: reports the supported base ISA and extensions."
  MIE -> "Machine interrupt-enable: per-source interrupt enable bits."
  MTVEC -> "Machine trap-vector base address: where the PC jumps on a trap."
  MSCRATCH -> "Machine scratch: a free register for trap handlers to stash a value."
  MEPC -> "Machine exception PC: the PC saved when a trap is taken."
  MCAUSE -> "Machine cause: the code identifying what caused the most recent trap."
  MTVAL -> "Machine trap value: faulting address or instruction bits for the trap."
  MIP -> "Machine interrupt-pending: per-source interrupt pending bits."

csrCatalogue :: [CsrInfo]
csrCatalogue =
  [ CsrInfo name ("0x" ++ showHex addr "") (csrDescription c)
    | c <- [minBound .. maxBound],
      let (name, addr) = csrInfo c
  ]

instance ToJSON CsrInfo where
  toJSON (CsrInfo name addr desc) =
    object
      [ "name" .= name,
        "address" .= addr,
        "description" .= desc
      ]
