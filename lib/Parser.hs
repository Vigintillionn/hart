module Parser where

import Types
import Control.Applicative
import Data.Char (isDigit, isAlpha, isAlphaNum, isHexDigit)
import Control.Monad (void)
import qualified Data.Map.Strict as M
import Text.Read (readMaybe)
import Numeric (readHex)
import GHC.Base (when)
import Machine

abiMap :: M.Map String Int
abiMap = M.fromList [
    ("zero", 0), ("ra", 1), ("sp", 2), ("gp", 3), ("tp", 4),
    ("t0", 5), ("t1", 6), ("t2", 7),
    ("s0", 8), ("fp", 8),
    ("s1", 9),
    ("a0", 10), ("a1", 11), ("a2", 12), ("a3", 13), ("a4", 14), ("a5", 15), 
    ("a6", 16), ("a7", 17),
    ("s2", 18), ("s3", 19), ("s4", 20), ("s5", 21), ("s6", 22), ("s7", 23),
    ("s8", 24), ("s9", 25), ("s10", 26), ("s11", 27),
    ("t3", 28), ("t4", 29), ("t5", 30), ("t6", 31)
    ]

newtype Parser a = Parser { runParser :: String -> Either AssemblyError (a, String) }

instance Functor Parser where
    fmap :: (a -> b) -> Parser a -> Parser b 
    fmap f (Parser pa) = Parser $ \input ->
        case pa input of
            Left err -> Left err
            Right (a, rest) -> Right (f a, rest)

instance Applicative Parser where
    pure :: a -> Parser a
    pure a = Parser $ \s -> Right (a, s) 

    (<*>) :: Parser (a -> b) -> Parser a -> Parser b
    (Parser pf) <*> (Parser pa) = Parser $ \input ->
        case pf input of
            Left err -> Left err
            Right (f, rest1) ->
                case pa rest1 of
                    Left err -> Left err
                    Right (a, rest2) -> Right (f a, rest2)

instance Monad Parser where
    return :: a -> Parser a
    return = pure

    (>>=) :: Parser a -> (a -> Parser b) -> Parser b
    (Parser pa) >>= f = Parser $ \input ->
        case pa input of
            Left err -> Left err
            Right (a, rest) ->
                let newParser = f a
                    (Parser pf) = newParser 
                in pf rest 

instance Alternative Parser where
    empty :: Parser a
    empty = Parser $ \_ -> Left EmptyParserFailed

    (<|>) :: Parser a -> Parser a -> Parser a
    (Parser pa) <|> (Parser pb) = Parser $ \input ->
        case pa input of
            Left _ -> pb input
            Right res -> Right res

instance MonadFail Parser where
    fail :: String -> Parser a
    fail msg = Parser $ \_ -> Left (ParserFail msg)

choice :: [Parser a] -> Parser a
choice = asum 

lookAhead :: Parser a -> Parser a
lookAhead (Parser p) = Parser $ \input ->
    case p input of
        Left err -> Left err
        Right (a, _) -> Right (a, input)

satisfy :: (Char -> Bool) -> Parser Char 
satisfy predicate = Parser $ \case 
        (c:cs) | predicate c -> Right (c, cs)
        (c:_)           -> Left (UnexpectedChar c)
        []              -> Left EOF 

char :: Char -> Parser Char
char c = satisfy (== c)

string :: String -> Parser String
string = traverse char 

identifier :: Parser String
identifier = some (satisfy (\c -> isAlphaNum c || c == '_'))

integer :: Parser Int
integer = do
    digits <- some (satisfy isDigit)
    case readMaybe digits of
        Just x  -> return x
        Nothing -> fail "Integer overflow or invalid number"


comma :: Parser ()
comma = void $ lexeme (char ',')

sc :: Parser ()
sc = void $ many (satisfy (`elem` " \t"))

lexeme :: Parser a -> Parser a
lexeme p = p <* sc 

comment :: Parser ()
comment = void $ char '#' *> many (satisfy (/= '\n'))

eof :: Parser ()
eof = Parser $ \s ->
    case s of
        []  -> Right((), s)
        _   -> Left (ParserFail $ "Expected end of file, but got: " ++ s)

register :: Parser Register 
register = lexeme $ choice [abiName, xName]
    where
        xName = char 'x' *> integer >>= \n -> maybe (fail "Invalid register name") return (mkRegister n)
        abiName = do
            name <- some (satisfy isAlpha)
            case M.lookup name abiMap of
                Just n -> case mkRegister n of
                    Nothing  -> fail "Invalid register name"
                    Just reg -> return reg
                Nothing -> fail "Invalid register name"

operand :: Parser Operand
operand = choice 
    [ ImmVal <$> immediate
    , Label <$> identifier
    ]

labelDef :: Parser String
labelDef = identifier <* char ':'

immediate :: Parser Int
immediate = do
    sign    <- optional (char '-')
    hex     <- optional (string "0x") 

    case hex of
        Just _ -> do
            digits <- some (satisfy isHexDigit)
            case readHex digits of
                [(x, "")]   -> return $ applySign sign x
                _           -> fail "Invalid Hex string"
        Nothing -> applySign sign <$> integer 
        where
            applySign (Just _) x  = -x
            applySign Nothing  x  = x

memOperand :: Parser (Operand, Register)
memOperand = do
    off <- operand
    void $ char '('
    base <- register
    void $ char ')'
    return (off, base)

csrOperand :: Parser Int
csrOperand = namedCSR <|> immediate
  where
    namedCSR = do
        name <- identifier
        case encodeCSR name of
            Just addr -> return addr
            Nothing   -> fail $ "Unknown CSR name: " ++ name

parseRTypeOperands :: Parser RTypeArgs
parseRTypeOperands = RTypeArgs 
    <$> register <* comma 
    <*> register <* comma 
    <*> register 

parseIArithTypeOperands :: Parser (ITypeArgs Operand)
parseIArithTypeOperands = ITypeArgs 
    <$> register <* comma
    <*> register <* comma
    <*> operand 

parseILoadTypeOperands :: Parser (ITypeArgs Operand)
parseILoadTypeOperands = do
    rd <- register
    comma
    (off, rs1) <- memOperand
    return $ ITypeArgs rd rs1 off 

parseIJumpTypeOperands :: Parser (ITypeArgs Operand)
parseIJumpTypeOperands = explicit <|> implicit
    where
        explicit = ITypeArgs
            <$> register <* comma
            <*> register <* comma
            <*> operand
        implicit = do
            rs <- register
            return $ ITypeArgs x1 rs (ImmVal 0)

parseBTypeOperands :: Parser (BTypeArgs Operand)
parseBTypeOperands = BTypeArgs
    <$> register <* comma
    <*> register <* comma
    <*> operand

parseSTypeOperands :: Parser (STypeArgs Operand)
parseSTypeOperands = do
    src <- register
    comma
    (off, base) <- memOperand
    return $ STypeArgs base src off 

parseUTypeOperands :: Parser (UTypeArgs Operand)
parseUTypeOperands = UTypeArgs
    <$> register <* comma
    <*> operand

parseJTypeOperands :: Parser (JTypeArgs Operand)
parseJTypeOperands = explicit <|> implicit
    where
        explicit = JTypeArgs
            <$> register <* comma
            <*> operand
        implicit = JTypeArgs x1 
            <$> operand

rType :: String -> (RTypeArgs -> Instruction 'R Operand) -> Parser (ArchInstr 'Parsed) 
rType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseRTypeOperands

iArithType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (ArchInstr 'Parsed)
iArithType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseIArithTypeOperands

iLoadType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (ArchInstr 'Parsed)
iLoadType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseILoadTypeOperands

iJmpType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (ArchInstr 'Parsed)
iJmpType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseIJumpTypeOperands

bType :: String -> (BTypeArgs Operand -> Instruction 'B Operand) -> Parser (ArchInstr 'Parsed)
bType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseBTypeOperands

sType :: String -> (STypeArgs Operand -> Instruction 'S Operand) -> Parser (ArchInstr 'Parsed)
sType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseSTypeOperands

uType :: String -> (UTypeArgs Operand -> Instruction 'U Operand) -> Parser (ArchInstr 'Parsed)
uType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseUTypeOperands

jType :: String -> (JTypeArgs Operand -> Instruction 'J Operand) -> Parser (ArchInstr 'Parsed)
jType n c = RealInstr . SomeInstruction . c <$ lexeme (string n) <*> parseJTypeOperands

pseudoType :: String -> Parser PseudoOp -> Parser (ArchInstr 'Parsed)
pseudoType n p = PseudoInstr <$> (lexeme (string n) *> p)

parseSystem :: SysOp -> Parser (ArchInstr 'Parsed)
parseSystem op = do
    rd  <- register
    comma
    csr <- csrOperand
    comma
    rs1 <- register
    
    let args = SysArgs { c_rd = rd, c_csr = csr, c_rs1 = rs1 }
    return $ RealInstr $ SomeInstruction $ System op args

parseSystemImm :: SysIOp -> Parser (ArchInstr 'Parsed)
parseSystemImm op = do
    rd   <- register
    comma
    csr  <- csrOperand
    comma
    uimm <- immediate 
    
    when (uimm < 0 || uimm > 31) $ 
        fail $ "CSR immediate must be 0-31, got: " ++ show uimm

    let args = SysIArgs { ci_rd = rd, ci_csr = csr, ci_uimm = ImmVal (fromIntegral uimm) }
    return $ RealInstr $ SomeInstruction $ SystemI op args

parseTrap :: TrapOp -> Parser (ArchInstr 'Parsed)
parseTrap op = return $ RealInstr $ SomeInstruction (Trap op)

parseNop :: Parser PseudoOp
parseNop = pure P_NOP 

parsePseudoDoubleReg :: (Register -> Register -> PseudoOp) -> Parser PseudoOp
parsePseudoDoubleReg op = op <$> register <* comma <*> register

parseLi :: Parser PseudoOp
parseLi = P_LI <$> register <* comma <*> operand

parseLa :: Parser PseudoOp
parseLa = P_LA <$> register <* comma <*> identifier

parseLoadGlobal :: ILoadOp -> Parser PseudoOp
parseLoadGlobal op = do
    rd <- register
    comma
    P_LOAD_GL op rd <$> identifier 

parseStoreGlobal :: SOp -> Parser PseudoOp
parseStoreGlobal op = do
    src <- register
    comma
    lbl <- identifier
    comma
    P_STORE_GL op src lbl <$> register 

parsePseudoBranchZero :: (Register -> Operand -> PseudoOp) -> Parser PseudoOp
parsePseudoBranchZero op = op <$> register <* comma <*> operand

parsePseudoBranchCompare :: (Register -> Register -> Operand -> PseudoOp) -> Parser PseudoOp
parsePseudoBranchCompare op = do
    args <- parseBTypeOperands
    return $ op (b_rs1 args) (b_rs2 args) (b_imm args)

parseInstruction :: Parser (ArchInstr 'Parsed) 
parseInstruction = choice $ concat 
    [ map (\(n, op) -> rType        n (RType op))   rOps
    , map (\(n, op) -> iArithType   n (ArithI op))  iArithOps
    , map (\(n, op) -> iLoadType    n (LoadI op))   iLoadOps
    , map (\(n, op) -> iJmpType     n (JumpI op))   iJmpOps
    , map (\(n, op) -> bType        n (BType op))   bOps 
    , map (\(n, op) -> sType        n (SType op))   sOps 
    , map (\(n, op) -> uType        n (UType op))   uOps
    , map (\(n, op) -> jType        n (JType op))   jOps
    , map (uncurry pseudoType) pseudoOps
    , map (\(n, op) -> lexeme (string n) >> parseSystemImm op) sysImmOps
    , map (\(n, op) -> lexeme (string n) >> parseSystem op)    sysOps
    , map (\(n, op) -> lexeme (string n) >> parseTrap op)      trapOps
    ]
    where
        rOps      = [ ("add", ADD), ("sub", SUB), ("xor", XOR), ("or", OR), ("and", AND)
                    , ("sll", SLL), ("srl", SRL), ("sra", SRA)
                    , ("slt", SLT), ("sltu",SLTU)
                    ]
        iArithOps = [ ("addi", ADDI), ("xori", XORI), ("ori", ORI), ("andi", ANDI)
                    , ("slli", SLLI), ("srli", SRLI), ("srai", SRAI)
                    , ("slti", SLTI), ("sltiu", SLTIU)
                    ]
        iLoadOps  = [ ("lbu", LBU), ("lhu", LHU) 
                    , ("lb", LB), ("lh", LH), ("lw", LW)
                    ]
        iJmpOps   = [("jalr", JALR)]
        bOps      = [ ("bltu", BLTU), ("bgeu", BGEU)
                    , ("beq", BEQ), ("bne", BNE), ("blt", BLT), ("bge", BGE)
                    ]
        sOps      = [("sb", SB), ("sh", SH), ("sw", SW)]
        uOps      = [("lui", LUI), ("auipc", AUIPC)]
        jOps      = [("jal", JAL)]
        sysImmOps = [ ("csrrwi", CSRRWI), ("csrrsi", CSRRSI), ("csrrci", CSRRCI) ]
        sysOps    = [ ("csrrw", CSRRW), ("csrrs", CSRRS), ("csrrc", CSRRC) ]
        trapOps   = [ ("ecall", ECALL), ("ebreak", EBREAK) ]
        pseudoOps = [ ("nop", parseNop), ("mv", parsePseudoDoubleReg P_MV), ("li", parseLi)
                    , ("neg", parsePseudoDoubleReg P_NEG), ("not", parsePseudoDoubleReg P_NOT)
                    , ("seqz", parsePseudoDoubleReg P_SEQZ), ("snez", parsePseudoDoubleReg P_SNEZ)
                    , ("sltz", parsePseudoDoubleReg P_SLTZ), ("sgtz", parsePseudoDoubleReg P_SGTZ)
                    , ("la", parseLa)
                    , ("lw",  parseLoadGlobal LW), ("lb",  parseLoadGlobal LB)
                    , ("lbu", parseLoadGlobal LBU), ("lh",  parseLoadGlobal LH)
                    , ("lhu", parseLoadGlobal LHU), ("sw",  parseStoreGlobal SW)
                    , ("sb",  parseStoreGlobal SB), ("sh",  parseStoreGlobal SH)
                    , ("beqz", parsePseudoBranchZero P_BEQZ), ("bnez", parsePseudoBranchZero P_BNEZ)
                    , ("blez", parsePseudoBranchZero P_BLEZ), ("bgez", parsePseudoBranchZero P_BGEZ)
                    , ("bltz", parsePseudoBranchZero P_BLTZ), ("bgtz", parsePseudoBranchZero P_BGTZ)
                    , ("bgt",  parsePseudoBranchCompare P_BGT), ("ble",  parsePseudoBranchCompare P_BLE)
                    , ("bgtu", parsePseudoBranchCompare P_BGTU), ("bleu", parsePseudoBranchCompare P_BLEU)
                    , ("call", P_CALL <$> lexeme (string "call")), ("tail", P_TAIL <$> lexeme (string "tail"))
                    ]

parseLine :: Parser SourceLine 
parseLine = do
    sc
    l <- optional labelDef
    sc
    i <- optional parseInstruction
    sc
    _ <- optional comment

    case (l, i) of
        (Nothing, Nothing) -> void (char '\n')
        _                  -> void (char '\n') <|> eof
    return (l, i)

parseProgram :: Parser [SourceLine]
parseProgram = do
    l <- many parseLine 
    eof
    return $ filter (not . isEmpty) l
    where
        isEmpty (Nothing, Nothing) = True
        isEmpty _                  = False

parse :: String -> Either AssemblyError [SourceLine] 
parse src = case runParser parseProgram src of
    Right (instr, left) -> case left of
        []  -> Right instr
        s   -> Left (ParserFail $ "Could not parse full source, left: " ++ s)
    Left err          -> Left err

