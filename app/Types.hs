{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE StandaloneDeriving #-}
module Types where

type Register = Int
type Immediate = Int 

data ROp = ADD | SUB | XOR deriving (Show, Eq)
data IOp = ADDI | SUBI        deriving (Show, Eq)

data RTypeArgs = RTypeArgs { r_rd :: Register, r_rs1 :: Register, r_rs2 :: Register }
    deriving (Show, Eq)
data ITypeArgs = ITypeArgs { i_rd :: Register, i_rs1 :: Register, i_imm :: Immediate }
    deriving (Show, Eq)

data InstrKind = R | I

data Instruction (k :: InstrKind) where
    RType :: ROp -> RTypeArgs -> Instruction 'R 
    IType :: IOp -> ITypeArgs -> Instruction 'I

deriving instance Show (Instruction k)
deriving instance Eq   (Instruction k)

data SomeInstruction where
  SomeInstruction :: Instruction k -> SomeInstruction

deriving instance Show SomeInstruction
instance Eq SomeInstruction where
  (SomeInstruction (RType o1 a1))  == (SomeInstruction (RType o2 a2))  = o1 == o2 && a1 == a2
  (SomeInstruction (IType o1 a1))  == (SomeInstruction (IType o2 a2))  = o1 == o2 && a1 == a2
  _ == _ = False

-- data Instruction
--     = ADD RTypeArgs  -- rd, rs1, rs2
--     | SUB RTypeArgs
--     | XOR RTypeArgs
--     | ADDI ITypeArgs -- rd, rs1, imm 
--     | SUBI ITypeArgs
--     deriving (Show, Eq)

data AssemblyError
    = UnknownInstruction String
    | InvalidRegister String
    | ImmediateTooLarge Int
    | UnexpectedChar Char
    | EmptyParserFailed
    | ParserFail String
    | EOF 
    deriving (Show, Eq)
