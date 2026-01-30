module Types (Register
             , mkRegister
             , unReg
             , Instruction(..)
             , InstrKind(..)
             , SourceLine
             , ParsedProgram
             , LoweredProgram
             , Program
             , SomeInstruction(..)
             , Operand(..)
             , ROp(..)
             , IArithOp(..)
             , ILoadOp(..)
             , IJmpOp(..)
             , BOp(..)
             , SOp(..)
             , UOp(..)
             , JOp(..)
             , RTypeArgs(..)
             , ITypeArgs(..)
             , BTypeArgs(..)
             , STypeArgs(..)
             , UTypeArgs(..)
             , JTypeArgs(..)
             , AssemblyError(..)
             , Phase(..)
             , ArchInstr(..)
             , PseudoOp(..)
             , x0
             , x1
             ) where

newtype Register = Reg { unReg :: Int } deriving (Show, Eq, Ord)

x0 :: Register
x0 = Reg 0

x1 :: Register
x1 = Reg 1

mkRegister :: Int -> Maybe Register
mkRegister n
    | n >= 0 && n < 32 = Just (Reg n)
    | otherwise        = Nothing

data Phase = Parsed | Lowered | Resolved

data Operand = ImmVal Int | Label String
    deriving (Show, Eq)

type family ImmOf (p :: Phase) where
    ImmOf 'Parsed   = Operand
    ImmOf 'Lowered  = Operand
    ImmOf 'Resolved = Int

data ROp = ADD | SUB | XOR | OR | AND       deriving (Show, Eq, Enum, Bounded)
data IArithOp = ADDI | XORI | ORI | ANDI    deriving (Show, Eq, Enum, Bounded)    
data ILoadOp = LB | LH | LW                 deriving (Show, Eq, Enum, Bounded)
data IJmpOp = JALR                          deriving (Show, Eq, Enum, Bounded)
data BOp = BEQ | BNE | BLT | BGE            deriving (Show, Eq, Enum, Bounded)
data SOp = SB | SH | SW                     deriving (Show, Eq, Enum, Bounded)
data UOp = LUI | AUIPC                      deriving (Show, Eq, Enum, Bounded)
data JOp = JAL                              deriving (Show, Eq, Enum, Bounded)

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

data InstrKind = R | I | B | S | U | J

data Instruction (k :: InstrKind) a where
    RType  :: ROp       -> RTypeArgs   -> Instruction 'R a
    ArithI :: IArithOp  -> ITypeArgs a -> Instruction 'I a
    LoadI  :: ILoadOp   -> ITypeArgs a -> Instruction 'I a
    JumpI  :: IJmpOp    -> ITypeArgs a -> Instruction 'I a 
    BType  :: BOp       -> BTypeArgs a -> Instruction 'B a
    SType  :: SOp       -> STypeArgs a -> Instruction 'S a
    UType  :: UOp       -> UTypeArgs a -> Instruction 'U a
    JType  :: JOp       -> JTypeArgs a -> Instruction 'J a

data PseudoOp = P_NOP
              | P_MV Register Register
              | P_LI Register Operand
              | P_NOT Register Register
              | P_NEG Register Register
              | P_J Operand
              | P_JR Register
              | P_RET

deriving instance Show a => Show (Instruction k a)
deriving instance Eq a => Eq (Instruction k a)

instance Functor (Instruction k) where
    fmap _ (RType op args)  = RType  op args
    fmap f (ArithI op args) = ArithI op (args { i_imm = f (i_imm args) })
    fmap f (LoadI op args)  = LoadI  op (args { i_imm = f (i_imm args) })
    fmap f (JumpI op args)  = JumpI  op (args { i_imm = f (i_imm args) })
    fmap f (BType op args)  = BType  op (args { b_imm = f (b_imm args) })
    fmap f (SType op args)  = SType  op (args { s_imm = f (s_imm args) })
    fmap f (UType op args)  = UType  op (args { u_imm = f (u_imm args) })
    fmap f (JType op args)  = JType  op (args { j_imm = f (j_imm args) })

instance Foldable (Instruction k) where
    foldMap _ (RType _ _)  = mempty
    foldMap f (ArithI _ a) = foldMap f a
    foldMap f (LoadI _ a)  = foldMap f a
    foldMap f (JumpI _ a)  = foldMap f a
    foldMap f (BType _ a)  = foldMap f a
    foldMap f (SType _ a)  = foldMap f a
    foldMap f (UType _ a)  = foldMap f a
    foldMap f (JType _ a)  = foldMap f a

instance Traversable (Instruction k) where
    traverse _ (RType op args)  = pure (RType op args)
    traverse f (ArithI op args) = ArithI op <$> traverse f args
    traverse f (LoadI op args)  = LoadI op  <$> traverse f args
    traverse f (JumpI op args)  = JumpI op  <$> traverse f args
    traverse f (BType op args)  = BType op  <$> traverse f args
    traverse f (SType op args)  = SType op  <$> traverse f args
    traverse f (UType op args)  = UType op  <$> traverse f args
    traverse f (JType op args)  = JType op  <$> traverse f args

data SomeInstruction a where
  SomeInstruction :: Instruction k a -> SomeInstruction a

data ArchInstr (p :: Phase) where
    RealInstr   :: SomeInstruction (ImmOf p) -> ArchInstr p
    PseudoInstr :: PseudoOp -> ArchInstr 'Parsed

deriving instance Show a => Show (SomeInstruction a)
instance Eq a => Eq (SomeInstruction a) where
  (SomeInstruction (RType o1 a1))  == (SomeInstruction (RType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (ArithI o1 a1)) == (SomeInstruction (ArithI o2 a2)) = o1 == o2 && a1 == a2
  (SomeInstruction (LoadI o1 a1))  == (SomeInstruction (LoadI o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (JumpI o1 a1))  == (SomeInstruction (JumpI o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (BType o1 a1))  == (SomeInstruction (BType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (SType o1 a1))  == (SomeInstruction (SType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (UType o1 a1))  == (SomeInstruction (UType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (JType o1 a1))  == (SomeInstruction (JType o2 a2))  = o1 == o2 && a1 == a2
  _ == _ = False

instance Functor SomeInstruction where
    fmap f (SomeInstruction i) = SomeInstruction (fmap f i)

instance Foldable SomeInstruction where
    foldMap f (SomeInstruction i) = foldMap f i

instance Traversable SomeInstruction where
    traverse f (SomeInstruction i) = SomeInstruction <$> traverse f i

-- Line might have a label, instruction, or both
type SourceLine = (Maybe String, Maybe (ArchInstr 'Parsed))
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
