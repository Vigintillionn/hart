module Parser (parse) where

import Control.Applicative
import Control.Monad (void)
import Data.Bifunctor (second)
import Data.Bits (bit, shiftR)
import Data.Char (isAlpha, isAlphaNum, isDigit, isHexDigit)
import Data.Map.Strict qualified as M
import Data.Maybe (mapMaybe)
import Error (AssemblyError (..))
import Extension (Extension (..), ExtensionSet, extensionCode, isEnabled)
import Extension.Classify (HasExtension (..))
import GHC.Base (when)
import Machine
import Numeric (readHex)
import Text.Read (readMaybe)
import Types

abiMap :: M.Map String Int
abiMap =
  M.fromList
    [ ("zero", 0),
      ("ra", 1),
      ("sp", 2),
      ("gp", 3),
      ("tp", 4),
      ("t0", 5),
      ("t1", 6),
      ("t2", 7),
      ("s0", 8),
      ("fp", 8),
      ("s1", 9),
      ("a0", 10),
      ("a1", 11),
      ("a2", 12),
      ("a3", 13),
      ("a4", 14),
      ("a5", 15),
      ("a6", 16),
      ("a7", 17),
      ("s2", 18),
      ("s3", 19),
      ("s4", 20),
      ("s5", 21),
      ("s6", 22),
      ("s7", 23),
      ("s8", 24),
      ("s9", 25),
      ("s10", 26),
      ("s11", 27),
      ("t3", 28),
      ("t4", 29),
      ("t5", 30),
      ("t6", 31)
    ]

-- | A parser failure, tagged with whether it is /committed/. A @Soft@ failure
-- means "this alternative didn't match, backtrack and try the next one"; a
-- @Hard@ failure means "we matched far enough to know this is the intended
-- production, so the error is real and must not be swallowed by '<|>',
-- 'optional', or 'many'". The 'Int' is the source line at the point of failure.
data PErr = PErr !Bool !Int !AssemblyError

newtype Parser a = Parser {runParser :: Int -> String -> Either PErr (a, Int, String)}

instance Functor Parser where
  fmap f (Parser pa) = Parser $ \l input ->
    case pa l input of
      Left err -> Left err
      Right (a, l', rest) -> Right (f a, l', rest)

instance Applicative Parser where
  pure a = Parser $ \l s -> Right (a, l, s)

  (Parser pf) <*> (Parser pa) = Parser $ \l input ->
    case pf l input of
      Left err -> Left err
      Right (f, l1, rest1) ->
        case pa l1 rest1 of
          Left err -> Left err
          Right (a, l2, rest2) -> Right (f a, l2, rest2)

instance Monad Parser where
  return = pure

  (Parser pa) >>= f = Parser $ \l input ->
    case pa l input of
      Left err -> Left err
      Right (a, l1, rest) ->
        let (Parser pf) = f a
         in pf l1 rest

instance Alternative Parser where
  empty = Parser $ \l _ -> Left (PErr False l EmptyParserFailed)

  (Parser pa) <|> (Parser pb) = Parser $ \l input ->
    case pa l input of
      Left (PErr False _ _) -> pb l input
      Left hard -> Left hard
      Right res -> Right res

instance MonadFail Parser where
  fail msg = Parser $ \l _ -> Left (PErr False l (ParserFail msg))

failWith :: AssemblyError -> Parser a
failWith e = Parser $ \l _ -> Left (PErr False l e)

failHard :: AssemblyError -> Parser a
failHard e = Parser $ \l _ -> Left (PErr True l e)

commit :: Parser a -> Parser a
commit (Parser p) = Parser $ \l s ->
  case p l s of
    Left (PErr _ el e) -> Left (PErr True el e)
    ok -> ok

choice :: [Parser a] -> Parser a
choice = asum

lookAhead :: Parser a -> Parser a
lookAhead (Parser p) = Parser $ \l input ->
  case p l input of
    Left err -> Left err
    Right (a, _, _) -> Right (a, l, input)

satisfy :: (Char -> Bool) -> Parser Char
satisfy predicate = Parser $ \l str -> case str of
  (c : cs) | predicate c -> Right (c, if c == '\n' then l + 1 else l, cs)
  (c : _) -> Left (PErr False l (UnexpectedChar c))
  [] -> Left (PErr False l EOF)

char :: Char -> Parser Char
char c = satisfy (== c)

string :: String -> Parser String
string = traverse char

isIdentChar :: Char -> Bool
isIdentChar c = isAlphaNum c || c == '_'

notFollowedBy :: Parser a -> Parser ()
notFollowedBy (Parser p) = Parser $ \l s ->
  case p l s of
    Left _ -> Right ((), l, s)
    Right _ -> Left (PErr False l EmptyParserFailed)

keyword :: String -> Parser ()
keyword n = lexeme (void (string n) <* notFollowedBy (satisfy isIdentChar))

identifier :: Parser String
identifier = some (satisfy isIdentChar)

integer :: Parser Int
integer = do
  digits <- some (satisfy isDigit)
  case readMaybe digits of
    Just x -> return x
    Nothing -> fail "Integer overflow or invalid number"

sepBy1 :: Parser a -> Parser sep -> Parser [a]
sepBy1 p sep = (:) <$> p <*> many (sep *> p)

comma :: Parser ()
comma = void $ lexeme (char ',')

sc :: Parser ()
sc = void $ many (blockComment <|> void (satisfy (`elem` " \t")))

lexeme :: Parser a -> Parser a
lexeme p = p <* sc

anyChar :: Parser Char
anyChar = satisfy (const True)

blockComment :: Parser ()
blockComment = string "/*" *> commit go
  where
    go = void (string "*/") <|> (anyChar *> go)

comment :: Parser ()
comment =
  void $
    (void (char '#') <|> void (string "//")) *> many (satisfy (/= '\n'))

escapeChar :: Parser Char
escapeChar = do
  void $ char '\\'
  c <- satisfy (`elem` "nt0\\\"")
  return $ case c of
    'n' -> '\n'
    't' -> '\t'
    '0' -> '\0'
    '\\' -> '\\'
    '"' -> '"'
    _ -> c

stringLiteral :: Parser String
stringLiteral = lexeme $ do
  void $ char '"'
  str <- many (escapeChar <|> satisfy (/= '"'))
  void $ char '"'
  return str

eof :: Parser ()
eof = Parser $ \l s ->
  case s of
    [] -> Right ((), l, s)
    _ -> Left (PErr False l (ParserFail (takeWhile (/= '\n') s)))

register :: Parser Register
register = lexeme $ do
  name <- some (satisfy isAlphaNum)
  case classify name of
    Just reg -> return reg
    Nothing -> failWith (InvalidRegister name)
  where
    classify name =
      (M.lookup name abiMap >>= mkRegister) <|> xName name
    xName ('x' : ds@(_ : _)) | all isDigit ds = readMaybe ds >>= mkRegister
    xName _ = Nothing

operand :: Parser Operand
operand =
  choice
    [ ImmVal <$> immediate,
      Label <$> identifier
    ]

labelDef :: Parser String
labelDef = identifier <* char ':'

immediate :: Parser Int
immediate = do
  sign <- optional (char '-')
  hex <- optional (string "0x")

  case hex of
    Just _ -> do
      digits <- some (satisfy isHexDigit)
      case readHex digits of
        [(x, "")] -> return $ applySign sign x
        _ -> fail "Invalid Hex string"
    Nothing -> applySign sign <$> integer
  where
    applySign (Just _) x = -x
    applySign Nothing x = x

memOperand :: Parser (Operand, Register)
memOperand = do
  off <- operand
  void $ char '('
  base <- register
  void $ char ')'
  return (off, base)

csrOperand :: Parser Int
csrOperand = do
  addr <- namedCSR <|> immediate
  when (addr < 0 || addr > 4095) $
    failWith (CsrOutOfRange "CSR address" 0 4095 addr)
  return addr
  where
    namedCSR = do
      name <- identifier
      case encodeCSR name of
        Just addr -> return addr
        Nothing -> fail $ "Unknown CSR name: " ++ name

parseRTypeOperands :: Parser RTypeArgs
parseRTypeOperands =
  RTypeArgs
    <$> register
    <* comma
    <*> register
    <* comma
    <*> register

parseIArithTypeOperands :: Parser (ITypeArgs Operand)
parseIArithTypeOperands =
  ITypeArgs
    <$> register
    <* comma
    <*> register
    <* comma
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
    explicit =
      ITypeArgs
        <$> register
        <* comma
        <*> register
        <* comma
        <*> operand
    implicit = do
      rs <- register
      return $ ITypeArgs x1 rs (ImmVal 0)

parseBTypeOperands :: Parser (BTypeArgs Operand)
parseBTypeOperands =
  BTypeArgs
    <$> register
    <* comma
    <*> register
    <* comma
    <*> operand

parseSTypeOperands :: Parser (STypeArgs Operand)
parseSTypeOperands = do
  src <- register
  comma
  (off, base) <- memOperand
  return $ STypeArgs base src off

parseUTypeOperands :: Parser (UTypeArgs Operand)
parseUTypeOperands =
  UTypeArgs
    <$> register
    <* comma
    <*> operand

parseJTypeOperands :: Parser (JTypeArgs Operand)
parseJTypeOperands = explicit <|> implicit
  where
    explicit =
      JTypeArgs
        <$> register
        <* comma
        <*> operand
    implicit =
      JTypeArgs x1
        <$> operand

rType :: String -> (RTypeArgs -> Instruction 'R Operand) -> Parser (ArchInstr 'Parsed)
rType n c = RealInstr . SomeInstruction . c <$ keyword n <*> commit parseRTypeOperands

iArithType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (ArchInstr 'Parsed)
iArithType n c = RealInstr . SomeInstruction . c <$ keyword n <*> commit parseIArithTypeOperands

-- | Load/store mnemonics are overloaded: the same word (@lw@, @sw@, …) is also
-- a pseudo-instruction taking a label. We must therefore /not/ commit here, so
-- a memory-operand mismatch can backtrack to the global-load/store pseudo.
iLoadType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (ArchInstr 'Parsed)
iLoadType n c = RealInstr . SomeInstruction . c <$ keyword n <*> parseILoadTypeOperands

iJmpType :: String -> (ITypeArgs Operand -> Instruction 'I Operand) -> Parser (ArchInstr 'Parsed)
iJmpType n c = RealInstr . SomeInstruction . c <$ keyword n <*> commit parseIJumpTypeOperands

bType :: String -> (BTypeArgs Operand -> Instruction 'B Operand) -> Parser (ArchInstr 'Parsed)
bType n c = RealInstr . SomeInstruction . c <$ keyword n <*> commit parseBTypeOperands

-- | See 'iLoadType' for why store operands are not committed.
sType :: String -> (STypeArgs Operand -> Instruction 'S Operand) -> Parser (ArchInstr 'Parsed)
sType n c = RealInstr . SomeInstruction . c <$ keyword n <*> parseSTypeOperands

uType :: String -> (UTypeArgs Operand -> Instruction 'U Operand) -> Parser (ArchInstr 'Parsed)
uType n c = RealInstr . SomeInstruction . c <$ keyword n <*> commit parseUTypeOperands

jType :: String -> (JTypeArgs Operand -> Instruction 'J Operand) -> Parser (ArchInstr 'Parsed)
jType n c = RealInstr . SomeInstruction . c <$ keyword n <*> commit parseJTypeOperands

pseudoType :: String -> Parser PseudoOp -> Parser (ArchInstr 'Parsed)
pseudoType n p = PseudoInstr <$> (keyword n *> commit p)

parseSystem :: SysOp -> Parser (ArchInstr 'Parsed)
parseSystem op = do
  rd <- register
  comma
  csr <- csrOperand
  comma
  rs1 <- register

  let args = SysArgs {c_rd = rd, c_csr = csr, c_rs1 = rs1}
  return $ RealInstr $ SomeInstruction $ System op args

parseSystemImm :: SysIOp -> Parser (ArchInstr 'Parsed)
parseSystemImm op = do
  rd <- register
  comma
  csr <- csrOperand
  comma
  uimm <- immediate

  when (uimm < 0 || uimm > 31) $
    failWith (CsrOutOfRange "CSR immediate" 0 31 uimm)

  let args = SysIArgs {ci_rd = rd, ci_csr = csr, ci_uimm = ImmVal (fromIntegral uimm)}
  return $ RealInstr $ SomeInstruction $ SystemI op args

parseTrap :: TrapOp -> Parser (ArchInstr 'Parsed)
parseTrap op = return $ RealInstr $ SomeInstruction (Trap op)

parseNop :: Parser PseudoOp
parseNop = pure P_NOP

parsePseudoDoubleReg :: (Register -> Register -> PseudoOp) -> Parser PseudoOp
parsePseudoDoubleReg op = op <$> register <* comma <*> register

parseLi :: Parser PseudoOp
parseLi = do
  rd <- register
  comma
  op <- operand
  case op of
    ImmVal v | not (liFits v) -> failWith (ImmediateTooLarge v)
    _ -> return ()
  return (P_LI rd op)
  where
    liFits v =
      let hi = (v + 0x800) `shiftR` 12
       in hi >= negate (bit 19) && hi <= bit 20 - 1

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

parseCsrRead :: Parser PseudoOp
parseCsrRead = P_CSRR <$> register <* comma <*> csrOperand

parseCsrReg :: (Int -> Register -> PseudoOp) -> Parser PseudoOp
parseCsrReg op = op <$> csrOperand <* comma <*> register

parseCsrImm :: (Int -> Operand -> PseudoOp) -> Parser PseudoOp
parseCsrImm op = op <$> csrOperand <* comma <*> csrUImm
  where
    csrUImm = do
      uimm <- immediate
      when (uimm < 0 || uimm > 31) $
        failWith (CsrOutOfRange "CSR immediate" 0 31 uimm)
      return $ ImmVal (fromIntegral uimm)

rOpTable :: [(String, ROp)]
rOpTable =
  [ ("add", ADD),
    ("sub", SUB),
    ("xor", XOR),
    ("or", OR),
    ("and", AND),
    ("sll", SLL),
    ("srl", SRL),
    ("sra", SRA),
    ("slt", SLT),
    ("sltu", SLTU),
    ("mul", MUL),
    ("mulh", MULH),
    ("mulhsu", MULHSU),
    ("mulhu", MULHU),
    ("div", DIV),
    ("divu", DIVU),
    ("rem", REM),
    ("remu", REMU)
  ]

iArithTable :: [(String, IArithOp)]
iArithTable =
  [ ("addi", ADDI),
    ("xori", XORI),
    ("ori", ORI),
    ("andi", ANDI),
    ("slli", SLLI),
    ("srli", SRLI),
    ("srai", SRAI),
    ("slti", SLTI),
    ("sltiu", SLTIU)
  ]

iLoadTable :: [(String, ILoadOp)]
iLoadTable =
  [ ("lbu", LBU),
    ("lhu", LHU),
    ("lb", LB),
    ("lh", LH),
    ("lw", LW)
  ]

iJmpTable :: [(String, IJmpOp)]
iJmpTable = [("jalr", JALR)]

bTable :: [(String, BOp)]
bTable =
  [ ("bltu", BLTU),
    ("bgeu", BGEU),
    ("beq", BEQ),
    ("bne", BNE),
    ("blt", BLT),
    ("bge", BGE)
  ]

sTable :: [(String, SOp)]
sTable = [("sb", SB), ("sh", SH), ("sw", SW)]

uTable :: [(String, UOp)]
uTable = [("lui", LUI), ("auipc", AUIPC)]

jTable :: [(String, JOp)]
jTable = [("jal", JAL)]

sysImmTable :: [(String, SysIOp)]
sysImmTable = [("csrrwi", CSRRWI), ("csrrsi", CSRRSI), ("csrrci", CSRRCI)]

sysTable :: [(String, SysOp)]
sysTable = [("csrrw", CSRRW), ("csrrs", CSRRS), ("csrrc", CSRRC)]

trapTable :: [(String, TrapOp)]
trapTable = [("ecall", ECALL), ("ebreak", EBREAK)]

extPseudoOps :: [(String, Parser PseudoOp, Extension)]
extPseudoOps =
  [ ("csrr", parseCsrRead, ZicsrExt),
    ("csrw", parseCsrReg P_CSRW, ZicsrExt),
    ("csrs", parseCsrReg P_CSRS, ZicsrExt),
    ("csrc", parseCsrReg P_CSRC, ZicsrExt),
    ("csrwi", parseCsrImm P_CSRWI, ZicsrExt),
    ("csrsi", parseCsrImm P_CSRSI, ZicsrExt),
    ("csrci", parseCsrImm P_CSRCI, ZicsrExt)
  ]

keepEnabled :: (HasExtension op) => ExtensionSet -> [(String, op)] -> [(String, op)]
keepEnabled exts = filter (\(_, op) -> isEnabled (extensionOf op) exts)

classifiedMnemonics :: [(String, Extension)]
classifiedMnemonics =
  concat
    [ tag rOpTable,
      tag iArithTable,
      tag iLoadTable,
      tag iJmpTable,
      tag bTable,
      tag sTable,
      tag uTable,
      tag jTable,
      tag sysImmTable,
      tag sysTable,
      tag trapTable,
      [(n, e) | (n, _, e) <- extPseudoOps]
    ]
  where
    tag :: (HasExtension op) => [(String, op)] -> [(String, Extension)]
    tag = map (second extensionOf)

parseInstruction :: ExtensionSet -> Parser (ArchInstr 'Parsed)
parseInstruction exts =
  choice $
    concat
      [ map (\(n, op) -> rType n (RType op)) (keep rOpTable),
        map (\(n, op) -> iArithType n (ArithI op)) (keep iArithTable),
        map (\(n, op) -> iLoadType n (LoadI op)) (keep iLoadTable),
        map (\(n, op) -> iJmpType n (JumpI op)) (keep iJmpTable),
        map (\(n, op) -> bType n (BType op)) (keep bTable),
        map (\(n, op) -> sType n (SType op)) (keep sTable),
        map (\(n, op) -> uType n (UType op)) (keep uTable),
        map (\(n, op) -> jType n (JType op)) (keep jTable),
        map (uncurry pseudoType) pseudoOps,
        map (uncurry pseudoType) enabledExtPseudos,
        map (\(n, op) -> keyword n >> commit (parseSystemImm op)) (keep sysImmTable),
        map (\(n, op) -> keyword n >> commit (parseSystem op)) (keep sysTable),
        map (\(n, op) -> keyword n >> parseTrap op) (keep trapTable)
      ]
  where
    keep :: (HasExtension op) => [(String, op)] -> [(String, op)]
    keep = keepEnabled exts
    enabledExtPseudos =
      [(n, p) | (n, p, e) <- extPseudoOps, isEnabled e exts]
    pseudoOps =
      [ ("nop", parseNop),
        ("mv", parsePseudoDoubleReg P_MV),
        ("li", parseLi),
        ("neg", parsePseudoDoubleReg P_NEG),
        ("not", parsePseudoDoubleReg P_NOT),
        ("seqz", parsePseudoDoubleReg P_SEQZ),
        ("snez", parsePseudoDoubleReg P_SNEZ),
        ("sltz", parsePseudoDoubleReg P_SLTZ),
        ("sgtz", parsePseudoDoubleReg P_SGTZ),
        ("la", parseLa),
        ("j", P_J <$> operand),
        ("jr", P_JR <$> register),
        ("ret", pure P_RET),
        ("lw", parseLoadGlobal LW),
        ("lb", parseLoadGlobal LB),
        ("lbu", parseLoadGlobal LBU),
        ("lh", parseLoadGlobal LH),
        ("lhu", parseLoadGlobal LHU),
        ("sw", parseStoreGlobal SW),
        ("sb", parseStoreGlobal SB),
        ("sh", parseStoreGlobal SH),
        ("beqz", parsePseudoBranchZero P_BEQZ),
        ("bnez", parsePseudoBranchZero P_BNEZ),
        ("blez", parsePseudoBranchZero P_BLEZ),
        ("bgez", parsePseudoBranchZero P_BGEZ),
        ("bltz", parsePseudoBranchZero P_BLTZ),
        ("bgtz", parsePseudoBranchZero P_BGTZ),
        ("bgt", parsePseudoBranchCompare P_BGT),
        ("ble", parsePseudoBranchCompare P_BLE),
        ("bgtu", parsePseudoBranchCompare P_BGTU),
        ("bleu", parsePseudoBranchCompare P_BLEU),
        ("call", P_CALL <$> identifier),
        ("tail", P_TAIL <$> identifier)
      ]

parseSection :: Parser Directive
parseSection =
  choice
    [ DirSection TextSection <$ lexeme (string ".text"),
      DirSection DataSection <$ lexeme (string ".data"),
      DirSection BssSection <$ lexeme (string ".bss")
    ]

symbolName :: Parser String
symbolName = lexeme identifier

parseSymbolValue :: (String -> Int -> Directive) -> Parser Directive
parseSymbolValue mk = mk <$> symbolName <* comma <*> immediate

parseDirective :: Parser Directive
parseDirective =
  choice
    [ parseSection,
      lexeme (string ".string") *> (DirString <$> stringLiteral),
      lexeme (string ".asciz") *> (DirString <$> stringLiteral),
      lexeme (string ".ascii") *> (DirAscii <$> stringLiteral),
      lexeme (string ".byte") *> (DirByte <$> sepBy1 immediate comma),
      lexeme (string ".half") *> (DirHalf <$> sepBy1 immediate comma),
      lexeme (string ".short") *> (DirHalf <$> sepBy1 immediate comma),
      lexeme (string ".word") *> (DirWord <$> sepBy1 immediate comma),
      lexeme (string ".space") *> (DirSpace <$> immediate),
      lexeme (string ".zero") *> (DirSpace <$> immediate),
      lexeme (string ".align") *> (DirAlign <$> immediate),
      lexeme (string ".equiv") *> parseSymbolValue DirEquiv,
      lexeme (string ".equ") *> parseSymbolValue DirEqu,
      lexeme (string ".set") *> parseSymbolValue DirEqu,
      lexeme (string ".global") *> (DirGlobl <$> sepBy1 symbolName comma),
      lexeme (string ".globl") *> (DirGlobl <$> sepBy1 symbolName comma),
      lexeme (string ".local") *> (DirLocal <$> sepBy1 symbolName comma),
      lexeme (string ".weak") *> (DirWeak <$> sepBy1 symbolName comma)
    ]

parseStatement :: ExtensionSet -> Parser Statement
parseStatement exts =
  (StmtDirective <$> parseDirective)
    <|> (StmtInstr <$> parseInstruction exts)
    <|> disabledExtensionInstr exts
    <|> unknownInstr

mnemonicLike :: Parser String
mnemonicLike = (:) <$> satisfy isAlpha <*> many (satisfy isIdentChar)

unknownInstr :: Parser Statement
unknownInstr = lookAhead mnemonicLike >>= failHard . UnknownInstruction

-- | Recognise a mnemonic that would be valid but belongs to an extension the
-- user has switched off, and report it with a dedicated error rather than the
-- generic "unknown instruction"
disabledExtensionInstr :: ExtensionSet -> Parser Statement
disabledExtensionInstr exts = case disabled of
  [] -> empty
  ms -> do
    name <- lookAhead mnemonicLike
    case lookup name ms of
      Just ext -> failHard (ExtensionDisabled (extensionCode ext) name)
      Nothing -> empty
  where
    disabled = mapMaybe keepDisabled classifiedMnemonics
    keepDisabled (n, ext)
      | isEnabled ext exts = Nothing
      | otherwise = Just (n, ext)

getLineNum :: Parser Int
getLineNum = Parser $ \l s -> Right (l, l, s)

parseLine :: ExtensionSet -> Parser (Int, SourceLine)
parseLine exts = do
  sc
  ln <- getLineNum
  l <- optional labelDef
  sc
  i <- optional (parseStatement exts)
  sc
  _ <- optional comment

  case (l, i) of
    (Nothing, Nothing) -> void (char '\n')
    _ -> void (char '\n') <|> eof
  return (ln, (l, i))

parseProgram :: ExtensionSet -> Parser [(Int, SourceLine)]
parseProgram exts = do
  l <- many (parseLine exts)
  eof
  return $ filter (not . isEmpty) l
  where
    isEmpty (_, (Nothing, Nothing)) = True
    isEmpty _ = False

parse :: ExtensionSet -> String -> Either AssemblyError [(Int, SourceLine)]
parse exts src = case runParser (parseProgram exts) 1 (normalizeNewlines src) of
  Right (instr, _, _) -> Right instr
  Left (PErr _ ln e) -> Left (Located ln e)

normalizeNewlines :: String -> String
normalizeNewlines [] = []
normalizeNewlines ('\r' : '\n' : rest) = '\n' : normalizeNewlines rest
normalizeNewlines ('\r' : rest) = '\n' : normalizeNewlines rest
normalizeNewlines (c : rest) = c : normalizeNewlines rest
