module Linker
  ( Executable (..),
    Symbol (..),
    SymType (..),
    SymBinding (..),
    resolve,
  )
where

import Control.Monad (foldM)
import Data.Bifunctor (first)
import Data.Bits (Bits (..))
import Data.Char (ord)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Word (Word32, Word8)
import Error (LinkError (..))
import Machine
import Types

data SymType = AddrSym | ConstSym
  deriving (Show, Eq)

data SymBinding = Local | Global | Weak
  deriving (Show, Eq)

data Symbol = Symbol
  { symValue :: !Int,
    symType :: !SymType,
    symBinding :: !SymBinding
  }
  deriving (Show, Eq)

type SymbolTable = M.Map String Symbol

data Executable = Executable
  { execProgram :: Program,
    execDataMem :: IM.IntMap Word8,
    execSourceMap :: [(Word32, Int)]
  }
  deriving (Show)

litOp :: Int -> Operand
litOp = OpExpr . EInt

hiOp, loOp :: String -> Operand
hiOp = OpHi . ESym
loOp = OpLo . ESym

foldOperand :: Operand -> Maybe Int
foldOperand (OpExpr e) = foldConst e
foldOperand _ = Nothing

lower :: ArchInstr 'Parsed -> NonEmpty (SomeInstruction Operand)
lower (RealInstr i) = i :| []
lower (PseudoInstr op) = case op of
  P_NOP -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (litOp 0))
  P_MV rd rs -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (litOp 0))
  P_LI rd imm
    | Just v <- foldOperand imm,
      v < -2048 || v > 2047 ->
        let hi = (v + 0x800) `shiftR` 12
            lo = (v .&. 0xFFF) - (if testBit v 11 then 0x1000 else 0)
         in SomeInstruction (UType LUI (UTypeArgs rd (litOp hi)))
              :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (litOp lo)))]
    | otherwise -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd x0 imm)
  P_NEG rd rs -> pure $ SomeInstruction $ RType SUB (RTypeArgs rd x0 rs)
  P_NOT rd rs -> pure $ SomeInstruction $ ArithI XORI (ITypeArgs rd rs (litOp (-1)))
  P_J off -> pure $ SomeInstruction $ JType JAL (JTypeArgs x0 off)
  P_JR rs -> pure $ SomeInstruction $ JumpI JALR (ITypeArgs x0 rs (litOp 0))
  P_RET -> pure $ SomeInstruction $ JumpI JALR (ITypeArgs x0 x1 (litOp 0))
  P_LA rd lbl ->
    SomeInstruction (UType AUIPC (UTypeArgs rd (hiOp lbl)))
      :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (loOp lbl)))]
  P_LOAD_GL lop rd lbl ->
    SomeInstruction (UType AUIPC (UTypeArgs rd (hiOp lbl)))
      :| [SomeInstruction (LoadI lop (ITypeArgs rd rd (loOp lbl)))]
  P_STORE_GL sop src lbl temp ->
    SomeInstruction (UType AUIPC (UTypeArgs temp (hiOp lbl)))
      :| [SomeInstruction (SType sop (STypeArgs temp src (loOp lbl)))]
  P_SEQZ rd rs -> pure $ SomeInstruction $ ArithI SLTIU (ITypeArgs rd rs (litOp 1))
  P_SNEZ rd rs -> pure $ SomeInstruction $ RType SLTU (RTypeArgs rd x0 rs)
  P_SLTZ rd rs -> pure $ SomeInstruction $ RType SLT (RTypeArgs rd rs x0)
  P_SGTZ rd rs -> pure $ SomeInstruction $ RType SLT (RTypeArgs rd x0 rs)
  P_BEQZ rs off -> pure $ SomeInstruction $ BType BEQ (BTypeArgs rs x0 off)
  P_BNEZ rs off -> pure $ SomeInstruction $ BType BNE (BTypeArgs rs x0 off)
  P_BLTZ rs off -> pure $ SomeInstruction $ BType BLT (BTypeArgs rs x0 off) -- rs < 0
  P_BGEZ rs off -> pure $ SomeInstruction $ BType BGE (BTypeArgs rs x0 off)
  P_BLEZ rs off -> pure $ SomeInstruction $ BType BGE (BTypeArgs x0 rs off)
  P_BGTZ rs off -> pure $ SomeInstruction $ BType BLT (BTypeArgs x0 rs off)
  P_BGT rs rt off -> pure $ SomeInstruction $ BType BLT (BTypeArgs rt rs off)
  P_BLE rs rt off -> pure $ SomeInstruction $ BType BGE (BTypeArgs rt rs off)
  P_BGTU rs rt off -> pure $ SomeInstruction $ BType BLTU (BTypeArgs rt rs off)
  P_BLEU rs rt off -> pure $ SomeInstruction $ BType BGEU (BTypeArgs rt rs off)
  P_CALL lbl ->
    SomeInstruction (UType AUIPC (UTypeArgs x1 (hiOp lbl)))
      :| [SomeInstruction (JumpI JALR (ITypeArgs x1 x1 (loOp lbl)))]
  P_TAIL lbl ->
    SomeInstruction (UType AUIPC (UTypeArgs x6 (hiOp lbl)))
      :| [SomeInstruction (JumpI JALR (ITypeArgs x0 x6 (loOp lbl)))]
  P_CSRR rd csr -> pure $ SomeInstruction $ System CSRRS (SysArgs rd csr x0)
  P_CSRW csr rs -> pure $ SomeInstruction $ System CSRRW (SysArgs x0 csr rs)
  P_CSRS csr rs -> pure $ SomeInstruction $ System CSRRS (SysArgs x0 csr rs)
  P_CSRC csr rs -> pure $ SomeInstruction $ System CSRRC (SysArgs x0 csr rs)
  P_CSRWI csr imm -> pure $ SomeInstruction $ SystemI CSRRWI (SysIArgs x0 csr imm)
  P_CSRSI csr imm -> pure $ SomeInstruction $ SystemI CSRRSI (SysIArgs x0 csr imm)
  P_CSRCI csr imm -> pure $ SomeInstruction $ SystemI CSRRCI (SysIArgs x0 csr imm)

dataBase :: Int
dataBase = 0x10000000

-- | Round @x@ up to the next multiple of @a@
alignUp :: Int -> Int -> Int
alignUp a x = case x `mod` a of
  0 -> x
  r -> x + (a - r)

bssPageAlign :: Int
bssPageAlign = 0x1000

atLine :: Int -> Either LinkError a -> Either LinkError a
atLine ln = first (LocatedLink ln)

dataSize :: Directive -> Int
dataSize d = case d of
  DirString s -> length s + 1
  DirAscii s -> length s
  DirByte es -> length es
  DirHalf es -> length es * 2
  DirWord es -> length es * 4
  _ -> 0

alignPadding :: Int -> Int -> Int
alignPadding pc n =
  let a = 2 ^ n
   in case pc `mod` a of
        0 -> 0
        r -> a - r

data Place = Place
  { pTextPC :: !Int,
    pDataPC :: !Int,
    pBssPC :: !Int,
    pSection :: !Section,
    pSyms :: !SymbolTable,
    -- | names that may not be redefined (labels and @.equiv@ constants)
    pLocked :: !(S.Set String),
    -- | declared bindings, applied to the symbol table once placement is done
    pBind :: !(M.Map String SymBinding),
    -- | expanded instructions in reverse order: (address, source line, instr)
    pInstrs :: ![(Int, Int, SomeInstruction Operand)],
    -- | emitting data directives in reverse order: (address, source line, dir),
    -- their bytes are produced in a second pass, once every symbol is known, so
    -- that data may reference forward symbols (e.g. @.word later_label@)d
    pDataDirs :: ![(Int, Int, Directive)],
    -- | labels defined in @.bss@ placed at offsets relative to 0 during the
    -- walk, then shifted onto the bss base (just past @.data@) afterwards
    pBssSyms :: !(S.Set String)
  }

initPlace :: Place
initPlace = Place 0 dataBase 0 TextSection M.empty S.empty M.empty [] [] S.empty

placePC :: Place -> Int
placePC p = case pSection p of
  TextSection -> pTextPC p
  DataSection -> pDataPC p
  BssSection -> pBssPC p

advance :: Int -> Place -> Place
advance n p = case pSection p of
  TextSection -> p {pTextPC = pTextPC p + n}
  DataSection -> p {pDataPC = pDataPC p + n}
  BssSection -> p {pBssPC = pBssPC p + n}

defLabel :: Int -> String -> Int -> Place -> Either LinkError Place
defLabel ln name addr p
  | S.member name (pLocked p) || M.member name (pSyms p) =
      Left (LocatedLink ln (DuplicateLabel name))
  | otherwise =
      Right
        p
          { pSyms = M.insert name (Symbol addr AddrSym Local) (pSyms p),
            pLocked = S.insert name (pLocked p)
          }

defConst :: Bool -> Int -> String -> Int -> Place -> Either LinkError Place
defConst redefinable ln name val p
  | redefinable =
      if S.member name (pLocked p)
        then Left (LocatedLink ln (DuplicateLabel name))
        else Right p {pSyms = M.insert name sym (pSyms p)}
  | M.member name (pSyms p) = Left (LocatedLink ln (DuplicateLabel name))
  | otherwise =
      Right
        p
          { pSyms = M.insert name sym (pSyms p),
            pLocked = S.insert name (pLocked p)
          }
  where
    sym = Symbol val ConstSym Local

declareBinding :: SymBinding -> [String] -> Place -> Place
declareBinding b names p = p {pBind = foldr (`M.insert` b) (pBind p) names}

placeStep :: Place -> (Int, SourceLine) -> Either LinkError Place
placeStep p (ln, (mLabel, mStmt)) = do
  let here = placePC p
  p1 <- maybe (Right p) (\name -> recordBss name <$> defLabel ln name here p) mLabel
  maybe (Right p1) (placeStmt ln here p1) mStmt
  where
    recordBss name q
      | pSection p == BssSection = q {pBssSyms = S.insert name (pBssSyms q)}
      | otherwise = q

placeStmt :: Int -> Int -> Place -> Statement -> Either LinkError Place
placeStmt ln here p stmt = case stmt of
  StmtDirective (DirSection sec) -> Right p {pSection = sec}
  StmtDirective (DirEqu name e) -> defineConst True name e
  StmtDirective (DirEquiv name e) -> defineConst False name e
  StmtDirective (DirGlobl names) -> Right (declareBinding Global names p)
  StmtDirective (DirLocal names) -> Right (declareBinding Local names p)
  StmtDirective (DirWeak names) -> Right (declareBinding Weak names p)
  StmtDirective (DirSpace e) -> (`advance` p) <$> layoutVal e
  StmtDirective (DirAlign e) -> (\n -> advance (alignPadding here n) p) <$> layoutVal e
  StmtDirective dir ->
    let recorded
          | pSection p == BssSection = p
          | otherwise = p {pDataDirs = (here, ln, dir) : pDataDirs p}
     in Right (advance (dataSize dir) recorded)
  StmtInstr i ->
    let subs = NE.toList (lower i)
        placed = zipWith (\k sub -> (here + 4 * k, ln, sub)) [0 ..] subs
     in Right (advance (4 * length subs) p {pInstrs = reverse placed ++ pInstrs p})
  where
    layoutVal e = atLine ln (evalExpr here (pSyms p) e)
    defineConst redefinable name e = do
      v <- layoutVal e
      defConst redefinable ln name v p

-- | The @n@ little-endian bytes of @x@
leBytes :: Int -> Int -> [Word8]
leBytes n x = [fromIntegral ((x `shiftR` (8 * k)) .&. 0xFF) | k <- [0 .. n - 1]]

emitDirective :: SymbolTable -> Int -> Directive -> Either LinkError [(Int, Word8)]
emitDirective syms base dir = case dir of
  DirString str -> Right (zip [base ..] (map (fromIntegral . ord) (str ++ "\0")))
  DirAscii str -> Right (zip [base ..] (map (fromIntegral . ord) str))
  DirByte es -> emitInts 1 ".byte value" es
  DirHalf es -> emitInts 2 ".half value" es
  DirWord es -> emitInts 4 ".word value" es
  _ -> Right []
  where
    emitInts width ctx es =
      concat <$> traverse one (zip [base, base + width ..] es)
      where
        lo = negate (bit (8 * width - 1))
        hi = bit (8 * width) - 1
        one (addr, e) = do
          v <- evalExpr addr syms e
          if v < lo || v > hi
            then Left (ImmOutOfRange ctx lo hi v)
            else Right (zip [addr ..] (leBytes width v))

applyBindings :: M.Map String SymBinding -> SymbolTable -> SymbolTable
applyBindings binds syms =
  M.foldrWithKey (\n b -> M.adjust (\sym -> sym {symBinding = b}) n) syms binds

-- | Shift every @.bss@ symbol from its relative offset onto the bss base, which
-- sits just past @.data@ (page-aligned)
placeBss :: Int -> S.Set String -> SymbolTable -> SymbolTable
placeBss base names syms = S.foldr rebase syms names
  where
    rebase = M.adjust (\sym -> sym {symValue = symValue sym + base})

resolve :: ParsedProgram -> Either LinkError Executable
resolve prog = do
  placed <- foldM placeStep initPlace prog
  let bssBase = alignUp bssPageAlign (pDataPC placed)
      syms =
        applyBindings (pBind placed) $
          placeBss bssBase (pBssSyms placed) (pSyms placed)
  dataMem <- foldM (emitInto syms) IM.empty (reverse (pDataDirs placed))
  resolvedWithLines <- mapM (resolveOne syms) (reverse (pInstrs placed))
  let program = map fst resolvedWithLines
      sourceMap = map snd resolvedWithLines
  return $ Executable program dataMem sourceMap
  where
    emitInto syms mem (addr, ln, dir) = do
      bytes <- atLine ln (emitDirective syms addr dir)
      Right (foldl' (\m (a, b) -> IM.insert a b m) mem bytes)
    resolveOne syms (addr, ln, instr) =
      atLine ln $ do
        r <- resolveOperand addr syms instr
        return (r, (fromIntegral addr, ln))

checkShiftBounds :: IArithOp -> Int -> Either LinkError Int
checkShiftBounds op val
  | op `elem` [SLLI, SRLI, SRAI] && (val < 0 || val > 31) =
      Left (ShiftOutOfRange val)
  | otherwise = Right val

isReloc :: Operand -> Bool
isReloc (OpHi _) = True
isReloc (OpLo _) = True
isReloc _ = False

checkSigned :: String -> Int -> Bool -> Operand -> Int -> Either LinkError Int
checkSigned ctx bits aligned orig v
  | isReloc orig = Right v
  | aligned && odd v = Left (MisalignedTarget ctx v)
  | v < lo || v > hi = Left (ImmOutOfRange ctx lo hi v)
  | otherwise = Right v
  where
    hi = bit (bits - 1) - 1
    lo = negate (bit (bits - 1))

checkUpper :: Operand -> Int -> Either LinkError Int
checkUpper orig v
  | isReloc orig = Right v
  | v < lo || v > hi = Left (ImmOutOfRange "upper immediate" lo hi v)
  | otherwise = Right v
  where
    lo = negate (bit 19)
    hi = bit 20 - 1

symValueOf :: SymbolTable -> String -> Either LinkError Int
symValueOf table l = maybe (Left (UndefinedLabel l)) (Right . symValue) (M.lookup l table)

evalExpr :: Int -> SymbolTable -> Expr -> Either LinkError Int
evalExpr loc table = go
  where
    go (EInt n) = Right n
    go ECur = Right loc
    go (ESym s) = symValueOf table s
    go (EUn o e) = applyUnOp o <$> go e
    go (EBin o a b) = do
      x <- go a
      y <- go b
      maybe (Left DivByZero) Right (applyBinOp o x y)

pcrelHi, pcrelLo :: Int -> Int -> Int
pcrelHi pc t = (t - pc + 0x800) `shiftR` 12
pcrelLo pc t = (t - pc + 4) .&. 0xFFF

absHi, absLo :: Int -> Int
absHi t = (t + 0x800) `shiftR` 12
absLo t = t .&. 0xFFF

resolveRelative :: Int -> SymbolTable -> Operand -> Either LinkError Int
resolveRelative pc table op = case op of
  OpExpr e -> case foldConst e of
    Just v -> Right v
    Nothing -> subtract pc <$> evalExpr pc table e
  OpHi e -> pcrelHi pc <$> evalExpr pc table e
  OpLo e -> pcrelLo pc <$> evalExpr pc table e

resolveImm :: Int -> SymbolTable -> Operand -> Either LinkError Int
resolveImm pc table op = case op of
  OpExpr e -> evalExpr pc table e
  OpHi e -> pcrelHi pc <$> evalExpr pc table e
  OpLo e -> pcrelLo pc <$> evalExpr pc table e

resolveAbsolute :: Int -> SymbolTable -> Operand -> Either LinkError Int
resolveAbsolute pc table op = case op of
  OpExpr e -> evalExpr pc table e
  OpHi e -> absHi <$> evalExpr pc table e
  OpLo e -> absLo <$> evalExpr pc table e

resolveOperand :: Int -> SymbolTable -> SomeInstruction Operand -> Either LinkError (SomeInstruction Int)
resolveOperand pc table (SomeInstruction (JType op args)) = do
  v <- resolveRelative pc table (j_imm args)
  v' <- checkSigned "jump" 21 True (j_imm args) v
  return $ SomeInstruction $ JType op (args {j_imm = v'})
resolveOperand pc table (SomeInstruction (BType op args)) = do
  v <- resolveRelative pc table (b_imm args)
  v' <- checkSigned "branch" 13 True (b_imm args) v
  return $ SomeInstruction $ BType op (args {b_imm = v'})
resolveOperand pc table (SomeInstruction (UType AUIPC args)) = do
  v <- resolveRelative pc table (u_imm args)
  v' <- checkUpper (u_imm args) v
  return $ SomeInstruction $ UType AUIPC (args {u_imm = v'})
resolveOperand pc table (SomeInstruction (UType LUI args)) = do
  v <- resolveAbsolute pc table (u_imm args)
  v' <- checkUpper (u_imm args) v
  return $ SomeInstruction $ UType LUI (args {u_imm = v'})
resolveOperand pc table (SomeInstruction (LoadI op args)) = do
  v <- resolveImm pc table (i_imm args)
  v' <- checkSigned "load offset" 12 False (i_imm args) v
  return $ SomeInstruction $ LoadI op (args {i_imm = v'})
resolveOperand pc table (SomeInstruction (JumpI op args)) = do
  v <- resolveImm pc table (i_imm args)
  v' <- checkSigned "jalr offset" 12 False (i_imm args) v
  return $ SomeInstruction $ JumpI op (args {i_imm = v'})
resolveOperand pc table (SomeInstruction (ArithI op args)) = do
  val <- resolveImm pc table (i_imm args)
  validVal <-
    if op `elem` [SLLI, SRLI, SRAI]
      then checkShiftBounds op val
      else checkSigned "immediate" 12 False (i_imm args) val
  return $ SomeInstruction $ ArithI op (args {i_imm = validVal})
resolveOperand pc table (SomeInstruction (SType op args)) = do
  v <- resolveImm pc table (s_imm args)
  v' <- checkSigned "store offset" 12 False (s_imm args) v
  return $ SomeInstruction $ SType op (args {s_imm = v'})
resolveOperand pc table (SomeInstruction instr) =
  SomeInstruction <$> traverse (resolveAbsolute pc table) instr
