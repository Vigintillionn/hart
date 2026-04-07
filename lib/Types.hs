module Types where
import Data.List (find)
import Numeric
import Machine (Register) 

data Phase = Parsed | Lowered | Resolved

data Operand = ImmVal Int 
             | Label String
             | LabelHi String -- %hi(symbol)
             | LabelLo String -- %lo(symbol)
    deriving (Show, Eq)

type family ImmOf (p :: Phase) where
    ImmOf 'Parsed   = Operand
    ImmOf 'Lowered  = Operand
    ImmOf 'Resolved = Int

data ROp = ADD | SUB | XOR | OR  | AND
         | SLL | SRL | SRA | SLT | SLTU     deriving (Show, Eq, Enum, Bounded)
data IArithOp = ADDI | XORI | ORI  | ANDI    
              | SLLI | SRLI | SRAI | SLTI 
              | SLTIU                       deriving (Show, Eq, Enum, Bounded)    
data ILoadOp = LB | LH | LW | LBU | LHU     deriving (Show, Eq, Enum, Bounded)
data IJmpOp = JALR                          deriving (Show, Eq, Enum, Bounded)
data BOp = BEQ | BNE | BLT | BGE
         | BLTU | BGEU                      deriving (Show, Eq, Enum, Bounded)
data SOp = SB | SH | SW                     deriving (Show, Eq, Enum, Bounded)
data UOp = LUI | AUIPC                      deriving (Show, Eq, Enum, Bounded)
data JOp = JAL                              deriving (Show, Eq, Enum, Bounded)
data SysOp = CSRRW  | CSRRS  | CSRRC        deriving (Show, Eq, Enum, Bounded)
data SysIOp = CSRRWI | CSRRSI | CSRRCI      deriving (Show, Eq, Enum, Bounded)
data TrapOp = ECALL  | EBREAK               deriving (Show, Eq, Enum, Bounded)

data RTypeArgs   = RTypeArgs { r_rd :: Register, r_rs1 :: Register, r_rs2 :: Register }
    deriving (Show, Eq)
data ITypeArgs a = ITypeArgs { i_rd :: Register, i_rs1 :: Register, i_imm :: a }
    deriving (Show, Eq, Functor, Foldable, Traversable)
data BTypeArgs a = BTypeArgs { b_rs1 :: Register, b_rs2 :: Register, b_imm :: a }
    deriving (Show, Eq, Functor, Foldable, Traversable)
data STypeArgs a = STypeArgs { s_rs1 :: Register, s_rs2 :: Register, s_imm :: a }
    deriving (Show, Eq, Functor, Foldable, Traversable)
data UTypeArgs a = UTypeArgs { u_rd :: Register, u_imm :: a }
    deriving (Show, Eq, Functor, Foldable, Traversable)
data JTypeArgs a = JTypeArgs { j_rd :: Register, j_imm :: a }
    deriving (Show, Eq, Functor, Foldable, Traversable)
data SysArgs     = SysArgs { c_rd :: Register, c_csr :: Int, c_rs1 :: Register }
    deriving (Show, Eq)
data SysIArgs  a = SysIArgs { ci_rd :: Register, ci_csr :: Int, ci_uimm :: a }
    deriving (Show, Eq, Functor, Foldable, Traversable)

data InstrKind = R | I | B | S | U | J | Sys 

data Instruction (k :: InstrKind) a where
    RType   :: ROp       -> RTypeArgs   -> Instruction 'R a
    ArithI  :: IArithOp  -> ITypeArgs a -> Instruction 'I a
    LoadI   :: ILoadOp   -> ITypeArgs a -> Instruction 'I a
    JumpI   :: IJmpOp    -> ITypeArgs a -> Instruction 'I a 
    BType   :: BOp       -> BTypeArgs a -> Instruction 'B a
    SType   :: SOp       -> STypeArgs a -> Instruction 'S a
    UType   :: UOp       -> UTypeArgs a -> Instruction 'U a
    JType   :: JOp       -> JTypeArgs a -> Instruction 'J a
    System  :: SysOp     -> SysArgs     -> Instruction 'Sys a
    SystemI :: SysIOp    -> SysIArgs a  -> Instruction 'Sys a
    Trap    :: TrapOp                   -> Instruction 'Sys a 

data PseudoOp = P_NOP
              | P_MV Register Register
              | P_LI Register Operand
              | P_NOT Register Register
              | P_NEG Register Register
              | P_J Operand
              | P_JR Register
              | P_RET
              | P_LA Register String 
              | P_LOAD_GL ILoadOp Register String
              | P_STORE_GL SOp Register String Register
              | P_SEQZ Register Register
              | P_SNEZ Register Register
              | P_SLTZ Register Register
              | P_SGTZ Register Register
              | P_BEQZ Register Operand
              | P_BNEZ Register Operand
              | P_BLEZ Register Operand
              | P_BGEZ Register Operand
              | P_BLTZ Register Operand
              | P_BGTZ Register Operand
              | P_BGT  Register Register Operand
              | P_BLE  Register Register Operand
              | P_BGTU Register Register Operand
              | P_BLEU Register Register Operand
              | P_CALL String
              | P_TAIL String

data Section = TextSection | DataSection | BssSection
    deriving (Show, Eq)

data Directive
    = DirSection Section
    | DirString String
    | DirAscii String
    | DirByte [Int]
    | DirHalf [Int]
    | DirWord [Int]
    | DirSpace Int
    | DirAlign Int
    deriving (Show, Eq)

data Statement
    = StmtInstr (ArchInstr 'Parsed)
    | StmtDirective Directive

deriving instance Show a => Show (Instruction k a)
deriving instance Eq a => Eq (Instruction k a)

instance Functor (Instruction k) where
    fmap _ (RType op args)   = RType  op args
    fmap f (ArithI op args)  = ArithI op (args { i_imm = f (i_imm args) })
    fmap f (LoadI op args)   = LoadI  op (args { i_imm = f (i_imm args) })
    fmap f (JumpI op args)   = JumpI  op (args { i_imm = f (i_imm args) })
    fmap f (BType op args)   = BType  op (args { b_imm = f (b_imm args) })
    fmap f (SType op args)   = SType  op (args { s_imm = f (s_imm args) })
    fmap f (UType op args)   = UType  op (args { u_imm = f (u_imm args) })
    fmap f (JType op args)   = JType  op (args { j_imm = f (j_imm args) })
    fmap _ (System op args)  = System op args
    fmap f (SystemI op args) = SystemI op (fmap f args)
    fmap _ (Trap op)         = Trap op

instance Foldable (Instruction k) where
    foldMap _ (RType _ _)      = mempty
    foldMap f (ArithI _ a)     = foldMap f a
    foldMap f (LoadI _ a)      = foldMap f a
    foldMap f (JumpI _ a)      = foldMap f a
    foldMap f (BType _ a)      = foldMap f a
    foldMap f (SType _ a)      = foldMap f a
    foldMap f (UType _ a)      = foldMap f a
    foldMap f (JType _ a)      = foldMap f a
    foldMap _ (System _ _)     = mempty
    foldMap f (SystemI _ args) = foldMap f args
    foldMap _ (Trap _)         = mempty

instance Traversable (Instruction k) where
    traverse _ (RType op args)   = pure (RType op args)
    traverse f (ArithI op args)  = ArithI op <$> traverse f args
    traverse f (LoadI op args)   = LoadI op  <$> traverse f args
    traverse f (JumpI op args)   = JumpI op  <$> traverse f args
    traverse f (BType op args)   = BType op  <$> traverse f args
    traverse f (SType op args)   = SType op  <$> traverse f args
    traverse f (UType op args)   = UType op  <$> traverse f args
    traverse f (JType op args)   = JType op  <$> traverse f args
    traverse _ (System op args)  = pure (System op args)
    traverse f (SystemI op args) = SystemI op <$> traverse f args
    traverse _ (Trap op)         = pure (Trap op)

data SomeInstruction a where
  SomeInstruction :: Instruction k a -> SomeInstruction a

data ArchInstr (p :: Phase) where
    RealInstr   :: SomeInstruction (ImmOf p) -> ArchInstr p
    PseudoInstr :: PseudoOp -> ArchInstr 'Parsed

deriving instance Show a => Show (SomeInstruction a)
instance Eq a => Eq (SomeInstruction a) where
  (SomeInstruction (RType o1 a1))   == (SomeInstruction (RType o2 a2))   = o1 == o2 && a1 == a2
  (SomeInstruction (ArithI o1 a1))  == (SomeInstruction (ArithI o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (LoadI o1 a1))   == (SomeInstruction (LoadI o2 a2))   = o1 == o2 && a1 == a2
  (SomeInstruction (JumpI o1 a1))   == (SomeInstruction (JumpI o2 a2))   = o1 == o2 && a1 == a2
  (SomeInstruction (BType o1 a1))   == (SomeInstruction (BType o2 a2))   = o1 == o2 && a1 == a2
  (SomeInstruction (SType o1 a1))   == (SomeInstruction (SType o2 a2))   = o1 == o2 && a1 == a2
  (SomeInstruction (UType o1 a1))   == (SomeInstruction (UType o2 a2))   = o1 == o2 && a1 == a2
  (SomeInstruction (JType o1 a1))   == (SomeInstruction (JType o2 a2))   = o1 == o2 && a1 == a2
  (SomeInstruction (System o1 a1))  == (SomeInstruction (System o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (SystemI o1 a1)) == (SomeInstruction (SystemI o2 a2)) = o1 == o2 && a1 == a2
  (SomeInstruction (Trap o1))       == (SomeInstruction (Trap o2))       = o1 == o2 
  _ == _ = False

instance Functor SomeInstruction where
    fmap f (SomeInstruction i) = SomeInstruction (fmap f i)

instance Foldable SomeInstruction where
    foldMap f (SomeInstruction i) = foldMap f i

instance Traversable SomeInstruction where
    traverse f (SomeInstruction i) = SomeInstruction <$> traverse f i

-- Line might have a label, instruction, or both
type SourceLine = (Maybe String, Maybe Statement)
type ParsedProgram = [SourceLine]
type LoweredProgram = [SomeInstruction Operand]
type Program = [SomeInstruction Int]

data AssemblyError
    = UnknownInstruction String
    | InvalidRegister String
    | ImmediateTooLarge Int
    | UnexpectedChar Char
    | EmptyParserFailed
    | ParserFail String
    | EOF 
    deriving (Show, Eq)

data CSRName 
    = MSTATUS | MISA | MIE | MTVEC | MSCRATCH | MEPC | MCAUSE | MTVAL | MIP 
    deriving (Show, Eq, Enum, Bounded)

csrInfo :: CSRName -> (String, Int)
csrInfo reg = case reg of
    MSTATUS  -> ("mstatus",  0x300)
    MISA     -> ("misa",     0x301)
    MIE      -> ("mie",      0x304)
    MTVEC    -> ("mtvec",    0x305)
    MSCRATCH -> ("mscratch", 0x340)
    MEPC     -> ("mepc",     0x341)
    MCAUSE   -> ("mcause",   0x342)
    MTVAL    -> ("mtval",    0x343)
    MIP      -> ("mip",      0x344)

encodeCSR :: String -> Maybe Int
encodeCSR name = 
    snd <$> find (\(n, _) -> n == name) allCSRs

decodeCSRName :: Int -> String
decodeCSRName addr = 
    case find (\(_, a) -> a == addr) allCSRs of
        Just (name, _) -> name
        Nothing        -> "0x" ++ showHex addr "" 

decodeCSR :: Int -> Maybe CSRName
decodeCSR addr = 
    fst <$> find (\(_, a) -> a == addr) allPairs
  where
    allPairs = [ (c, a) | c <- [minBound .. maxBound], let (_, a) = csrInfo c ]

allCSRs :: [(String, Int)]
allCSRs = [ csrInfo c | c <- [minBound .. maxBound] ]
