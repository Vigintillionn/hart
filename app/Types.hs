module Types where

newtype Register = Reg { unReg :: Int } deriving (Show, Eq, Ord)

mkRegister :: Int -> Maybe Register
mkRegister n
    | n >= 0 && n < 32 = Just (Reg n)
    | otherwise        = Nothing

data Operand = Immediate Int | Label String
    deriving (Show, Eq)

data ROp = ADD | SUB | XOR | OR | AND  deriving (Show, Eq)
data IOp = ADDI | XORI | ORI | ANDI    deriving (Show, Eq)
data BOp = BEQ | BNE                   deriving (Show, Eq)

data RTypeArgs = RTypeArgs { r_rd :: Register, r_rs1 :: Register, r_rs2 :: Register }
    deriving (Show, Eq)
data ITypeArgs = ITypeArgs { i_rd :: Register, i_rs1 :: Register, i_imm :: Operand }
    deriving (Show, Eq)
data BTypeArgs = BTypeArgs { b_rs1 :: Register, b_rs2 :: Register, b_imm :: Operand }
    deriving (Show, Eq)

data InstrKind = R | I | B

data Instruction (k :: InstrKind) where
    RType :: ROp -> RTypeArgs -> Instruction 'R 
    IType :: IOp -> ITypeArgs -> Instruction 'I
    BType :: BOp -> BTypeArgs -> Instruction 'B

deriving instance Show (Instruction k)
deriving instance Eq   (Instruction k)

data SomeInstruction where
  SomeInstruction :: Instruction k -> SomeInstruction

deriving instance Show SomeInstruction
instance Eq SomeInstruction where
  (SomeInstruction (RType o1 a1))  == (SomeInstruction (RType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (IType o1 a1))  == (SomeInstruction (IType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (BType o1 a1))  == (SomeInstruction (BType o2 a2))  = o1 == o2 && a1 == a2
  _ == _ = False

-- Line might have a label, instruction, or both
type SourceLine = (Maybe String, Maybe SomeInstruction)
type Program = [SomeInstruction]

data AssemblyError
    = UnknownInstruction String
    | InvalidRegister String
    | ImmediateTooLarge Int
    | UnexpectedChar Char
    | EmptyParserFailed
    | ParserFail String
    | EOF 
    deriving (Show, Eq)
