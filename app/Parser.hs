{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
module Parser where

import Types
import Control.Applicative
import Data.Char (isDigit, isAlpha, isAlphaNum, isHexDigit)
import Control.Monad (void)
import Data.Maybe (catMaybes)
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
satisfy predicate = Parser $ \input ->
    case input of
        (c:cs) | predicate c -> Right (c, cs)
        (c:_)           -> Left (UnexpectedChar c)
        []              -> Left EOF 

char :: Char -> Parser Char
char c = satisfy (== c)

string :: String -> Parser String
string = traverse char 

identifier :: Parser String
identifier = many (satisfy isAlphaNum)

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

eol :: Parser ()
eol = do
    sc
    _ <- optional comment
    void (char '\n') <|> eof
    return ()

eof :: Parser ()
eof = Parser $ \s ->
    case s of
        []  -> Right((), s)
        _   -> Left (ParserFail $ "Expected end of file, but got: " ++ s)

register :: Parser Int
register = lexeme $ choice [abiName, xName]
    where
        xName = char 'x' *> integer 
        abiName = do
            name <- some (satisfy isAlpha)
            case M.lookup name abiMap of
                Just reg -> return reg
                Nothing -> fail "Invalid register name"

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

parseRTypeOperands :: Parser RTypeArgs
parseRTypeOperands = RTypeArgs 
    <$> register <* comma 
    <*> register <* comma 
    <*> register 

parseITypeOperands :: Parser ITypeArgs
parseITypeOperands = ITypeArgs 
    <$> register <* comma
    <*> register <* comma
    <*> immediate

rType :: String -> (RTypeArgs -> Instruction 'R) -> Parser SomeInstruction 
rType n c = SomeInstruction . c <$ lexeme (string n) <*> parseRTypeOperands

iType :: String -> (ITypeArgs -> Instruction 'I) -> Parser SomeInstruction
iType n c = SomeInstruction . c <$ lexeme (string n) <*> parseITypeOperands

parseInstruction :: Parser SomeInstruction 
parseInstruction = choice [
        rType "add" (RType ADD),   
        rType "sub" (RType SUB),
        rType "xor" (RType XOR),

        iType "addi" (IType ADDI)
    ] 

parseLine :: Parser (Maybe SomeInstruction)
parseLine = do
    sc
    next <- optional (lookAhead (char '\n' <|> char '#'))

    case next of
        Just _  -> eol >> return Nothing -- empty line or comment
        Nothing -> do
            instr <- parseInstruction
            eol
            return (Just instr)

parseProgram :: Parser [SomeInstruction]
parseProgram = do
    l <- many parseLine 
    eof
    return (catMaybes l)

parse :: String -> Either AssemblyError [SomeInstruction] 
parse src = case runParser parseProgram src of
    Right (instr, left) -> case left of
        []  -> Right instr
        s   -> Left (ParserFail $ "Could not parse full source, left: " ++ s)
    Left err          -> Left err

