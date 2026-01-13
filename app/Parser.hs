module Parser where

import Types
import Control.Applicative
import Data.Char (isDigit, isAlpha, isAlphaNum, isHexDigit)
import Control.Monad (void)
import qualified Data.Map.Strict as M
import Text.Read (readMaybe)
import Numeric (readHex)

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
identifier = some (satisfy isAlphaNum)

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

rType :: String -> (RTypeArgs -> Instruction 'R Operand) -> Parser (SomeInstruction Operand) 
rType n c = SomeInstruction . c <$ lexeme (string n) <*> parseRTypeOperands

iArithType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (SomeInstruction Operand)
iArithType n c = SomeInstruction . c <$ lexeme (string n) <*> parseIArithTypeOperands

iLoadType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (SomeInstruction Operand)
iLoadType n c = SomeInstruction . c <$ lexeme (string n) <*> parseILoadTypeOperands

bType :: String -> (BTypeArgs Operand -> Instruction 'B Operand) -> Parser (SomeInstruction Operand)
bType n c = SomeInstruction . c <$ lexeme (string n) <*> parseBTypeOperands

sType :: String -> (STypeArgs Operand -> Instruction 'S Operand) -> Parser (SomeInstruction Operand)
sType n c = SomeInstruction . c <$ lexeme (string n) <*> parseSTypeOperands

parseInstruction :: Parser (SomeInstruction Operand) 
parseInstruction = choice $ concat 
    [ map (\(n, op) -> rType        n (RType op))   rOps
    , map (\(n, op) -> iArithType   n (ArithI op))  iArithOps
    , map (\(n, op) -> iLoadType    n (LoadI op))   iLoadOps
    , map (\(n, op) -> bType        n (BType op))   bOps 
    , map (\(n, op) -> sType        n (SType op))   sOps 
    ]
    where
        rOps = [("add", ADD), ("sub", SUB), ("xor", XOR), ("or", OR), ("and", AND)]
        iArithOps = [("addi", ADDI), ("xori", XORI), ("ori", ORI), ("andi", ANDI)]
        iLoadOps = [("lb", LB), ("lh", LH), ("lw", LW)]
        bOps = [("beq", BEQ), ("bne", BNE)]
        sOps = [("sb", SB), ("sh", SH), ("sw", SW)]

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

