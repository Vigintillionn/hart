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

stmtSize :: Int -> Statement -> Int
stmtSize _ (StmtInstr i) = sum (map (const 4) (NE.toList $ lower i))
stmtSize _ (StmtDirective (DirSection _)) = 0
stmtSize _ (StmtDirective (DirString s)) = length s + 1
stmtSize _ (StmtDirective (DirAscii s)) = length s
stmtSize _ (StmtDirective (DirByte l)) = length l
stmtSize _ (StmtDirective (DirHalf l)) = length l * 2
stmtSize _ (StmtDirective (DirWord l)) = length l * 4
stmtSize _ (StmtDirective (DirSpace n)) = n
stmtSize pc (StmtDirective (DirAlign n)) =
  let alignVal = 2 ^ n
      remAlign = pc `mod` alignVal
   in if remAlign == 0 then 0 else alignVal - remAlign
stmtSize _ (StmtDirective DirEqu {}) = 0
stmtSize _ (StmtDirective DirEquiv {}) = 0
stmtSize _ (StmtDirective (DirGlobl _)) = 0
stmtSize _ (StmtDirective (DirLocal _)) = 0
stmtSize _ (StmtDirective (DirWeak _)) = 0

lower :: ArchInstr 'Parsed -> NonEmpty (SomeInstruction Operand)
lower (RealInstr i) = i :| []
lower (PseudoInstr op) = case op of
  P_NOP -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (ImmVal 0))
  P_MV rd rs -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (ImmVal 0))
  P_LI rd (ImmVal v)
    | v < -2048 || v > 2047 ->
        let hi = (v + 0x800) `shiftR` 12
            lo = (v .&. 0xFFF) - (if testBit v 11 then 0x1000 else 0)
         in SomeInstruction (UType LUI (UTypeArgs rd (ImmVal hi)))
              :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (ImmVal lo)))]
  P_LI rd imm -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd x0 imm)
  P_NEG rd rs -> pure $ SomeInstruction $ RType SUB (RTypeArgs rd x0 rs)
  P_NOT rd rs -> pure $ SomeInstruction $ ArithI XORI (ITypeArgs rd rs (ImmVal (-1)))
  P_J off -> pure $ SomeInstruction $ JType JAL (JTypeArgs x0 off)
  P_JR rs -> pure $ SomeInstruction $ JumpI JALR (ITypeArgs x0 rs (ImmVal 0))
  P_RET -> pure $ SomeInstruction $ JumpI JALR (ITypeArgs x0 x1 (ImmVal 0))
  P_LA rd lbl ->
    SomeInstruction (UType AUIPC (UTypeArgs rd (LabelHi lbl)))
      :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (LabelLo lbl)))]
  P_LOAD_GL lop rd lbl ->
    SomeInstruction (UType AUIPC (UTypeArgs rd (LabelHi lbl)))
      :| [SomeInstruction (LoadI lop (ITypeArgs rd rd (LabelLo lbl)))]
  P_STORE_GL sop src lbl temp ->
    SomeInstruction (UType AUIPC (UTypeArgs temp (LabelHi lbl)))
      :| [SomeInstruction (SType sop (STypeArgs temp src (LabelLo lbl)))]
  P_SEQZ rd rs -> pure $ SomeInstruction $ ArithI SLTIU (ITypeArgs rd rs (ImmVal 1))
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
    SomeInstruction (UType AUIPC (UTypeArgs x1 (LabelHi lbl)))
      :| [SomeInstruction (JumpI JALR (ITypeArgs x1 x1 (LabelLo lbl)))]
  P_TAIL lbl ->
    SomeInstruction (UType AUIPC (UTypeArgs x6 (LabelHi lbl)))
      :| [SomeInstruction (JumpI JALR (ITypeArgs x0 x6 (LabelLo lbl)))]
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

-- | The first address past the @.data@ section, where @.bss@ begins (word-aligned)
dataEnd :: ParsedProgram -> Int
dataEnd = go dataBase TextSection
  where
    go acc _ [] = acc
    go acc sec ((_, (_, ms)) : rest) = case ms of
      Just (StmtDirective (DirSection sec')) -> go acc sec' rest
      Just stmt
        | sec == DataSection -> go (acc + stmtSize acc stmt) sec rest
        | otherwise -> go acc sec rest
      Nothing -> go acc sec rest

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
    pData :: !(IM.IntMap Word8)
  }

initPlace :: Int -> Place
initPlace bssBase = Place 0 dataBase bssBase TextSection M.empty S.empty M.empty [] IM.empty

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
  p1 <- maybe (Right p) (\name -> defLabel ln name here p) mLabel
  maybe (Right p1) (placeStmt ln here p1) mStmt

placeStmt :: Int -> Int -> Place -> Statement -> Either LinkError Place
placeStmt ln here p stmt = case stmt of
  StmtDirective (DirSection sec) -> Right p {pSection = sec}
  StmtDirective (DirEqu name val) -> defConst True ln name val p
  StmtDirective (DirEquiv name val) -> defConst False ln name val p
  StmtDirective (DirGlobl names) -> Right (declareBinding Global names p)
  StmtDirective (DirLocal names) -> Right (declareBinding Local names p)
  StmtDirective (DirWeak names) -> Right (declareBinding Weak names p)
  StmtDirective dir ->
    -- .bss is NOBITS: reserve space but emit no bytes.
    let p' = if pSection p == BssSection then p else p {pData = emitData here dir (pData p)}
     in Right (advance (stmtSize here (StmtDirective dir)) p')
  StmtInstr i ->
    let subs = NE.toList (lower i)
        placed = zipWith (\k sub -> (here + 4 * k, ln, sub)) [0 ..] subs
     in Right (advance (4 * length subs) p {pInstrs = reverse placed ++ pInstrs p})

emitData :: Int -> Directive -> IM.IntMap Word8 -> IM.IntMap Word8
emitData pc dir mem = case dir of
  DirString str -> putBytes (map (fromIntegral . ord) (str ++ "\0"))
  DirAscii str -> putBytes (map (fromIntegral . ord) str)
  DirByte xs -> putBytes (map fromIntegral xs)
  DirHalf xs -> putBytes (concatMap (leBytes 2) xs)
  DirWord xs -> putBytes (concatMap (leBytes 4) xs)
  _ -> mem
  where
    putBytes bs = foldl' (\m (i, b) -> IM.insert (pc + i) b m) mem (zip [0 ..] bs)

-- | The @n@ little-endian bytes of @x@
leBytes :: Int -> Int -> [Word8]
leBytes n x = [fromIntegral ((x `shiftR` (8 * k)) .&. 0xFF) | k <- [0 .. n - 1]]

applyBindings :: M.Map String SymBinding -> SymbolTable -> SymbolTable
applyBindings binds syms =
  M.foldrWithKey (\n b -> M.adjust (\sym -> sym {symBinding = b}) n) syms binds

resolve :: ParsedProgram -> Either LinkError Executable
resolve prog = do
  placed <- foldM placeStep (initPlace (alignUp 4 (dataEnd prog))) prog
  let syms = applyBindings (pBind placed) (pSyms placed)
  resolvedWithLines <- mapM (resolveOne syms) (reverse (pInstrs placed))
  let program = map fst resolvedWithLines
      sourceMap = map snd resolvedWithLines
  return $ Executable program (pData placed) sourceMap
  where
    resolveOne syms (addr, ln, instr) =
      first (LocatedLink ln) $ do
        r <- resolveOperand addr syms instr
        return (r, (fromIntegral addr, ln))

checkShiftBounds :: IArithOp -> Int -> Either LinkError Int
checkShiftBounds op val
  | op `elem` [SLLI, SRLI, SRAI] && (val < 0 || val > 31) =
      Left (ShiftOutOfRange val)
  | otherwise = Right val

isReloc :: Operand -> Bool
isReloc (LabelHi _) = True
isReloc (LabelLo _) = True
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

resolveRelative :: Int -> SymbolTable -> Operand -> Either LinkError Int
resolveRelative _ _ (ImmVal v) = Right v
resolveRelative pc table (Label l) = subtract pc <$> symValueOf table l
resolveRelative pc table (LabelHi l) = (\t -> (t - pc + 0x800) `shiftR` 12) <$> symValueOf table l
resolveRelative pc table (LabelLo l) = (\t -> (t - pc + 4) .&. 0xFFF) <$> symValueOf table l

resolveImm :: Int -> SymbolTable -> Operand -> Either LinkError Int
resolveImm _ _ (ImmVal v) = Right v
resolveImm _ table (Label l) = symValueOf table l
resolveImm pc table (LabelHi l) = (\t -> (t - pc + 0x800) `shiftR` 12) <$> symValueOf table l
resolveImm pc table (LabelLo l) = (\t -> (t - pc + 4) .&. 0xFFF) <$> symValueOf table l

resolveAbsolute :: SymbolTable -> Operand -> Either LinkError Int
resolveAbsolute _ (ImmVal v) = Right v
resolveAbsolute table (Label l) = symValueOf table l
resolveAbsolute table (LabelHi l) = (\t -> (t + 0x800) `shiftR` 12) <$> symValueOf table l
resolveAbsolute table (LabelLo l) = (.&. 0xFFF) <$> symValueOf table l

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
resolveOperand _ table (SomeInstruction (UType LUI args)) = do
  v <- resolveAbsolute table (u_imm args)
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
resolveOperand _ table (SomeInstruction instr) =
  SomeInstruction <$> traverse (resolveAbsolute table) instr
