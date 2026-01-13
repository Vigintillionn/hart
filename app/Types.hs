module Types (Register
             , mkRegister
             , unReg
             , Instruction(..)
             , InstrKind(..)
             , SourceLine
             , ParsedProgram
             , Program
             , SomeInstruction(..)
             , Operand(..)
             , ROp(..)
             , IArithOp(..)
             , ILoadOp(..)
             , BOp(..)
             , SOp(..)
             , RTypeArgs(..)
             , ITypeArgs(..)
             , BTypeArgs(..)
             , STypeArgs(..)
             , AssemblyError(..)
             ) where

newtype Register = Reg { unReg :: Int } deriving (Show, Eq, Ord)

mkRegister :: Int -> Maybe Register
mkRegister n
    | n >= 0 && n < 32 = Just (Reg n)
    | otherwise        = Nothing

data Operand = ImmVal Int | Label String
    deriving (Show, Eq)

data ROp = ADD | SUB | XOR | OR | AND       deriving (Show, Eq)
data IArithOp = ADDI | XORI | ORI | ANDI    deriving (Show,Eq)    
data ILoadOp = LB | LH | LW                 deriving (Show, Eq)
data BOp = BEQ | BNE | BLT | BGE            deriving (Show, Eq)
data SOp = SB | SH | SW                     deriving (Show, Eq)

data RTypeArgs = RTypeArgs { r_rd :: Register, r_rs1 :: Register, r_rs2 :: Register }
    deriving (Show, Eq)
data ITypeArgs a = ITypeArgs { i_rd :: Register, i_rs1 :: Register, i_imm :: a }
    deriving (Show, Eq)
data BTypeArgs a = BTypeArgs { b_rs1 :: Register, b_rs2 :: Register, b_imm :: a }
    deriving (Show, Eq)
data STypeArgs a = STypeArgs { s_rs1 :: Register, s_rs2 :: Register, s_imm :: a }
    deriving (Show, Eq)

data InstrKind = R | I | B | S

data Instruction (k :: InstrKind) a where
    RType  :: ROp       -> RTypeArgs   -> Instruction 'R a
    ArithI :: IArithOp  -> ITypeArgs a -> Instruction 'I a
    LoadI  :: ILoadOp   -> ITypeArgs a -> Instruction 'I a
    BType  :: BOp       -> BTypeArgs a -> Instruction 'B a
    SType  :: SOp       -> STypeArgs a -> Instruction 'S a

deriving instance Show a => Show (Instruction k a)
deriving instance Eq a => Eq (Instruction k a)

instance Functor (Instruction k) where
    fmap _ (RType op args)  = RType op args
    fmap f (ArithI op args) = ArithI op (args { i_imm = f (i_imm args) })
    fmap f (LoadI op args)  = LoadI op (args { i_imm = f (i_imm args) })
    fmap f (BType op args)  = BType op (args { b_imm = f (b_imm args) })
    fmap f (SType op args)  = SType op (args { s_imm = f (s_imm args) })

data SomeInstruction a where
  SomeInstruction :: Instruction k a -> SomeInstruction a

deriving instance Show a => Show (SomeInstruction a)
instance Eq a => Eq (SomeInstruction a) where
  (SomeInstruction (RType o1 a1))  == (SomeInstruction (RType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (ArithI o1 a1)) == (SomeInstruction (ArithI o2 a2)) = o1 == o2 && a1 == a2
  (SomeInstruction (LoadI o1 a1))  == (SomeInstruction (LoadI o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (BType o1 a1))  == (SomeInstruction (BType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (SType o1 a1))  == (SomeInstruction (SType o2 a2))  = o1 == o2 && a1 == a2
  _ == _ = False

instance Functor SomeInstruction where
    fmap f (SomeInstruction i) = SomeInstruction (fmap f i)

-- Line might have a label, instruction, or both
type SourceLine = (Maybe String, Maybe (SomeInstruction Operand))
type ParsedProgram = [SourceLine]
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
