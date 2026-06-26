module Linker
  ( Executable (..),
    Symbol (..),
    SymType (..),
    SymBinding (..),
    resolve,
  )
where

import Control.Monad (foldM)
import Control.Monad.State.Strict (StateT, execStateT, get, gets, lift, modify')
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
import Loc (Loc, locFile, locLine)
import Machine
import Types

data SymType
  = -- | a label: 'symValue' is its section-relative offset
    AddrSym
  | -- | a constant whose value is already known: 'symValue' holds it
    ConstSym
  | -- | a constant whose definition (with @.@ already substituted) still refers
    -- to a symbol that was forward at definition time; it is resolved lazily,
    -- against the complete table, the first time its value is needed
    DeferredSym Expr
  deriving (Show, Eq)

data SymBinding = Local | Global | Weak
  deriving (Show, Eq)

data Symbol = Symbol
  { -- | the section the symbol is defined in, or 'Nothing' for an absolute
    -- constant (@.equ@/@.set@/@.equiv@)
    symSection :: !(Maybe Section),
    -- | a section-relative offset for a label, or the absolute value for a constant
    symValue :: !Int,
    symType :: !SymType,
    symBinding :: !SymBinding
  }
  deriving (Show, Eq)

type SymbolTable = M.Map String Symbol

-- | the final base address assigned to each section, produced once all section sizes are known
-- sections absent from the map sit at base @0@
type SectionBases = M.Map Section Int

baseOf :: SectionBases -> Section -> Int
baseOf bases sec = M.findWithDefault 0 sec bases

-- | the absolute address of a symbol given the assigned section bases
symAbsolute :: SectionBases -> Symbol -> Int
symAbsolute bases sym = case symSection sym of
  Just sec -> baseOf bases sec + symValue sym
  Nothing -> symValue sym

data Executable = Executable
  { execProgram :: Program,
    execDataMem :: IM.IntMap Word8,
    -- | per-instruction provenance: (load address, source line, source file)
    execSourceMap :: [(Word32, Int, FilePath)]
  }
  deriving (Show)

litOp :: Int -> Operand
litOp = OpExpr . EInt

hiOp, loOp :: String -> Operand
hiOp = OpReloc HiPcrel . ESym
loOp = OpReloc LoPcrel . ESym

-- | split a value into the @(hi20, lo12)@ pair, with @lo@ sign-extended into [-2048, 2047]
hiLo12 :: Int -> (Int, Int)
hiLo12 v = ((v + 0x800) `shiftR` 12, (v .&. 0xFFF) - if testBit v 11 then 0x1000 else 0)

liHi, liLo :: Expr -> Expr
liHi e = EBin Shr (EBin Add e (EInt 0x800)) (EInt 12)
liLo e = EBin Sub (EBin BAnd (EBin Add e (EInt 0x800)) (EInt 0xFFF)) (EInt 0x800)

lower :: ArchInstr 'Parsed -> NonEmpty (SomeInstruction Operand)
lower (RealInstr i) = i :| []
lower (PseudoInstr op) = case op of
  P_NOP -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (litOp 0))
  P_MV rd rs -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (litOp 0))
  P_LI rd imm -> case imm of
    -- a constant we can fold now: emit the size-optimal form
    OpExpr e
      | Just v <- foldConst e ->
          if v < -2048 || v > 2047
            then
              let (hi, lo) = hiLo12 v
               in SomeInstruction (UType LUI (UTypeArgs rd (litOp hi)))
                    :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (litOp lo)))]
            else pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd x0 (litOp v))
    -- a symbol/expression whose value is unknown at lowering: emit the worst case (lui+addi)
    OpExpr e ->
      SomeInstruction (UType LUI (UTypeArgs rd (OpExpr (liHi e))))
        :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (OpExpr (liLo e))))]
    _ -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd x0 imm)
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

sectionAlign :: Int
sectionAlign = 4

atLoc :: Loc -> Either LinkError a -> Either LinkError a
atLoc loc = first (LocatedLink loc)

dataSize :: Directive -> Int
dataSize d = case d of
  DirString s -> length s + 1
  DirAscii s -> length s
  DirByte es -> length es
  DirHalf es -> length es * 2
  DirWord es -> length es * 4
  DirSection {} -> 0
  DirSpace {} -> 0
  DirAlign {} -> 0
  DirComm {} -> 0
  DirEqu {} -> 0
  DirEquiv {} -> 0
  DirGlobl {} -> 0
  DirLocal {} -> 0
  DirWeak {} -> 0

-- | the padding needed to bring @addr@ up to a multiple of @a@ bytes
padTo :: Int -> Int -> Int
padTo a addr
  | a <= 1 = 0
  | otherwise = case addr `mod` a of
      0 -> 0
      r -> a - r

-- | the byte alignment an alignment directive's argument denotes; the exponent is assumed non-negative
alignBytes :: AlignMode -> Int -> Int
alignBytes AlignPow2 e = 2 ^ e
alignBytes AlignBytes n = n

-- | how an alignment directive's argument is described in a diagnostic
alignCtx :: AlignMode -> String
alignCtx AlignPow2 = "alignment exponent"
alignCtx AlignBytes = "alignment"

-- | default alignment for a @.comm@/@.lcomm@ symbol
defaultCommAlign :: Int -> Int
defaultCommAlign size
  | size >= 4 = 4
  | size >= 2 = 2
  | otherwise = 1

data Place = Place
  { -- | the section bases in force for this walk (empty while sizes are being measured, so every section sits at base 0)
    pBases :: !SectionBases,
    -- | current byte offset within each visited section
    pOffsets :: !(M.Map Section Int),
    -- | the strongest alignment (in bytes) requested within each section
    pAligns :: !(M.Map Section Int),
    -- | visited sections in reverse first-seen order (reversed when read), used to lay out each region
    pOrder :: ![Section],
    pCur :: !Section,
    pSyms :: !SymbolTable,
    -- | names that may not be redefined (labels and @.equiv@ constants)
    pLocked :: !(S.Set String),
    -- | declared bindings, applied to the symbol table once placement is done
    pBind :: !(M.Map String SymBinding),
    -- | expanded instructions in reverse order: (address, source loc, instr)
    pInstrs :: ![(Int, Loc, SomeInstruction Operand)],
    -- | emitting data directives in reverse order: (address, source loc, dir),
    -- their bytes are produced in a second pass, once every symbol is known, so
    -- that data may reference forward symbols (e.g. @.word later_label@)
    pDataDirs :: ![(Int, Loc, Directive)]
  }

initPlace :: SectionBases -> Place
initPlace bases =
  Place
    { pBases = bases,
      pOffsets = M.singleton textSection 0,
      pAligns = M.empty,
      pOrder = [textSection],
      pCur = textSection,
      pSyms = M.empty,
      pLocked = S.empty,
      pBind = M.empty,
      pInstrs = [],
      pDataDirs = []
    }

type PlaceM = StateT Place (Either LinkError)

throw :: LinkError -> PlaceM a
throw = lift . Left

-- | the current byte offset within @sec@ (0 if it has not been visited yet)
offsetOf :: Section -> Place -> Int
offsetOf sec p = M.findWithDefault 0 sec (pOffsets p)

curOffset :: Place -> Int
curOffset p = offsetOf (pCur p) p

-- | the absolute address of the current point in the current section
placeAddr :: Place -> Int
placeAddr p = baseOf (pBases p) (pCur p) + curOffset p

-- | advance the current section's offset by @n@ bytes
advance :: Int -> PlaceM ()
advance n = modify' $ \p -> p {pOffsets = M.insertWith (+) (pCur p) n (pOffsets p)}

-- | record that @sec@ needs at least @a@-byte alignment
noteAlign :: Section -> Int -> Place -> Place
noteAlign sec a p = p {pAligns = M.insertWith max sec a (pAligns p)}

-- | register a section (assigning it offset 0 and a slot in the layout order) the first time it is seen
visitSection :: Section -> Place -> Place
visitSection sec p
  | M.member sec (pOffsets p) = p
  | otherwise =
      p
        { pOffsets = M.insert sec 0 (pOffsets p),
          pOrder = sec : pOrder p
        }

setSection :: Section -> Place -> Place
setSection sec p = (visitSection sec p) {pCur = sec}

-- | define an address symbol (a label or common symbol) at a section-relative offset, rejecting a redefinition
defAddrSym :: Loc -> String -> Section -> Int -> SymBinding -> PlaceM ()
defAddrSym loc name sec off bind = do
  taken <- gets (\p -> S.member name (pLocked p) || M.member name (pSyms p))
  if taken
    then throw (LocatedLink loc (DuplicateLabel name))
    else modify' $ \p ->
      p
        { pSyms = M.insert name (Symbol (Just sec) off AddrSym bind) (pSyms p),
          pLocked = S.insert name (pLocked p)
        }

defLabel :: Loc -> String -> PlaceM ()
defLabel loc name = do
  p <- get
  defAddrSym loc name (pCur p) (curOffset p) Local

-- | reserve a @.comm@/@.lcomm@ common symbol, does not change the current section
reserveCommon :: Loc -> Bool -> String -> Int -> Int -> PlaceM ()
reserveCommon loc isLocal name size align = do
  let a = max 1 align
      bind = if isLocal then Local else Global
  modify' (noteAlign commonSection a . visitSection commonSection)
  aligned <- gets (alignUp a . offsetOf commonSection)
  defAddrSym loc name commonSection aligned bind
  modify' $ \p -> p {pOffsets = M.insert commonSection (aligned + size) (pOffsets p)}

defConst :: Bool -> Loc -> String -> Symbol -> PlaceM ()
defConst redefinable loc name sym
  | redefinable = do
      locked <- gets (S.member name . pLocked)
      if locked
        then throw (LocatedLink loc (DuplicateLabel name))
        else modify' $ \p -> p {pSyms = M.insert name sym (pSyms p)}
  | otherwise = do
      defined <- gets (M.member name . pSyms)
      if defined
        then throw (LocatedLink loc (DuplicateLabel name))
        else modify' $ \p ->
          p
            { pSyms = M.insert name sym (pSyms p),
              pLocked = S.insert name (pLocked p)
            }

-- | replace the location counter @.@ in an expression with a literal
substCur :: Int -> Expr -> Expr
substCur loc = go
  where
    go ECur = EInt loc
    go (EUn o e) = EUn o (go e)
    go (EBin o a b) = EBin o (go a) (go b)
    go e = e

declareBinding :: SymBinding -> [String] -> Place -> Place
declareBinding b names p = p {pBind = foldr (`M.insert` b) (pBind p) names}

placeStep :: (Loc, SourceLine) -> PlaceM ()
placeStep (loc, (mLabel, mStmt)) = do
  mapM_ (defLabel loc) mLabel
  here <- gets placeAddr
  mapM_ (placeStmt loc here) mStmt

placeStmt :: Loc -> Int -> Statement -> PlaceM ()
placeStmt loc here stmt = case stmt of
  StmtDirective (DirSection sec) -> modify' (setSection sec)
  StmtDirective (DirEqu name e) -> defineConst True name e
  StmtDirective (DirEquiv name e) -> defineConst False name e
  StmtDirective (DirGlobl names) -> modify' (declareBinding Global names)
  StmtDirective (DirLocal names) -> modify' (declareBinding Local names)
  StmtDirective (DirWeak names) -> modify' (declareBinding Weak names)
  StmtDirective (DirSpace e) -> do
    n <- layoutVal e >>= requireNonNeg ".space size"
    advance n
  StmtDirective (DirAlign mode e) -> do
    v <- layoutVal e >>= requireNonNeg (alignCtx mode)
    let a = alignBytes mode v
    cur <- gets pCur
    modify' (noteAlign cur a)
    advance (padTo a here)
  StmtDirective (DirComm isLocal name sizeE mAlignE) -> do
    size <- layoutVal sizeE
    align <- maybe (pure (defaultCommAlign size)) layoutVal mAlignE
    reserveCommon loc isLocal name size align
  StmtDirective dir -> do
    inBss <- gets ((== SecBss) . secClass . pCur)
    -- bss is NOBITS: record the directive for emission only when it carries bytes
    modify' $ \p ->
      if inBss then p else p {pDataDirs = (here, loc, dir) : pDataDirs p}
    advance (dataSize dir)
  StmtInstr i -> do
    let subs = NE.toList (lower i)
        placed = zipWith (\k sub -> (here + 4 * k, loc, sub)) [0 ..] subs
    modify' $ \p -> p {pInstrs = reverse placed ++ pInstrs p}
    advance (4 * length subs)
  where
    layoutVal e = do
      p <- get
      lift (atLoc loc (evalExpr (pBases p) here (pSyms p) e))
    requireNonNeg ctx v
      | v < 0 = throw (LocatedLink loc (NegativeValue ctx v))
      | otherwise = pure v
    -- a constant is evaluated eagerly when every symbol it names is already defined
    defineConst redefinable name e0 = do
      p <- get
      let e = substCur here e0
      case evalExpr (pBases p) here (pSyms p) e of
        Right v -> defConst redefinable loc name (Symbol Nothing v ConstSym Local)
        Left (UndefinedLabel _) ->
          defConst redefinable loc name (Symbol Nothing 0 (DeferredSym e) Local)
        Left err -> throw (LocatedLink loc err)

-- | The @n@ little-endian bytes of @x@
leBytes :: Int -> Int -> [Word8]
leBytes n x = [fromIntegral ((x `shiftR` (8 * k)) .&. 0xFF) | k <- [0 .. n - 1]]

emitDirective :: SectionBases -> SymbolTable -> Int -> Directive -> Either LinkError [(Int, Word8)]
emitDirective bases syms base dir = case dir of
  DirString str -> Right (zip [base ..] (map (fromIntegral . ord) (str ++ "\0")))
  DirAscii str -> Right (zip [base ..] (map (fromIntegral . ord) str))
  DirByte es -> emitInts 1 ".byte value" es
  DirHalf es -> emitInts 2 ".half value" es
  DirWord es -> emitInts 4 ".word value" es
  DirSection {} -> Right []
  DirSpace {} -> Right []
  DirAlign {} -> Right []
  DirComm {} -> Right []
  DirEqu {} -> Right []
  DirEquiv {} -> Right []
  DirGlobl {} -> Right []
  DirLocal {} -> Right []
  DirWeak {} -> Right []
  where
    emitInts width ctx es =
      concat <$> traverse one (zip [base, base + width ..] es)
      where
        lo = negate (bit (8 * width - 1))
        hi = bit (8 * width) - 1
        one (addr, e) = do
          v <- evalExpr bases addr syms e
          if v < lo || v > hi
            then Left (ImmOutOfRange ctx lo hi v)
            else Right (zip [addr ..] (leBytes width v))

applyBindings :: M.Map String SymBinding -> SymbolTable -> SymbolTable
applyBindings binds syms =
  M.foldrWithKey (\n b -> M.adjust (\sym -> sym {symBinding = b}) n) syms binds

-- | assign each section a final base address from its measured size
-- * text-class sections fill the region from @entryPoint@
-- * rodata then data fill the region from @dataBase@
-- * bss-class sections follow, page-aligned, as NOBITS reservations.
assignBases :: M.Map Section Int -> M.Map Section Int -> [Section] -> SectionBases
assignBases sizes aligns order = M.unions [textB, rodB, datB, bssB]
  where
    sizeOf s = M.findWithDefault 0 s sizes
    -- a base must honour both the region's word alignment and any coarser
    -- alignment requested inside the section, else intra-section offsets shift
    alignOf s = max sectionAlign (M.findWithDefault 1 s aligns)
    inClass cls = filter ((== cls) . secClass) order
    layoutRegion start = foldl' step (M.empty, start)
      where
        step (m, cur) s =
          let b = alignUp (alignOf s) cur
           in (M.insert s b m, b + sizeOf s)
    (textB, _) = layoutRegion (fromIntegral entryPoint) (inClass SecText)
    (rodB, afterRod) = layoutRegion dataBase (inClass SecRodata)
    (datB, afterDat) = layoutRegion afterRod (inClass SecData)
    bssStart = alignUp bssPageAlign afterDat
    (bssB, _) = layoutRegion bssStart (inClass SecBss)

resolve :: ParsedProgram -> Either LinkError Executable
resolve prog = do
  -- walk with every section at base 0 purely to measure sizes
  measured <- execStateT walk (initPlace M.empty)
  let bases = assignBases (pOffsets measured) (pAligns measured) (reverse (pOrder measured))
  -- walk again with real bases, so every recorded address, and any @.equ@ referencing a label, is already absolute
  placed <- execStateT walk (initPlace bases)
  let syms = applyBindings (pBind placed) (pSyms placed)
  dataMem <- foldM (emitInto bases syms) IM.empty (reverse (pDataDirs placed))
  resolvedWithLines <- mapM (resolveOne bases syms) (reverse (pInstrs placed))
  let program = map fst resolvedWithLines
      sourceMap = map snd resolvedWithLines
  return $ Executable program dataMem sourceMap
  where
    walk = mapM_ placeStep prog
    emitInto bases syms mem (addr, loc, dir) = do
      bytes <- atLoc loc (emitDirective bases syms addr dir)
      Right (foldl' (\m (a, b) -> IM.insert a b m) mem bytes)
    resolveOne bases syms (addr, loc, instr) =
      atLoc loc $ do
        r <- resolveOperand bases addr syms instr
        return (r, (fromIntegral addr, locLine loc, locFile loc))

checkShiftBounds :: Int -> Either LinkError Int
checkShiftBounds val
  | val < 0 || val > 31 = Left (ShiftOutOfRange val)
  | otherwise = Right val

isReloc :: Operand -> Bool
isReloc (OpReloc _ _) = True
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

evalExpr :: SectionBases -> Int -> SymbolTable -> Expr -> Either LinkError Int
evalExpr bases loc table = go S.empty
  where
    -- @seen@ is the set of deferred constants currently being resolved, so a
    -- constant that refers back to itself is reported rather than looping
    go _ (EInt n) = Right n
    go _ ECur = Right loc
    go seen (ESym s) = resolveSym seen s
    go seen (EUn o e) = applyUnOp o <$> go seen e
    go seen (EBin o a b) = do
      x <- go seen a
      y <- go seen b
      maybe (Left DivByZero) Right (applyBinOp o x y)
    resolveSym seen s = case M.lookup s table of
      Nothing -> Left (UndefinedLabel s)
      Just sym -> case symType sym of
        DeferredSym e
          | S.member s seen -> Left (CircularConstant s)
          | otherwise -> go (S.insert s seen) e
        _ -> Right (symAbsolute bases sym)

pcrelHi, pcrelLo :: Int -> Int -> Int
pcrelHi pc t = (t - pc + 0x800) `shiftR` 12
pcrelLo pc t = (t - pc + 4) .&. 0xFFF

absHi, absLo :: Int -> Int
absHi = fst . hiLo12
absLo t = t .&. 0xFFF

relocValue :: RelocKind -> Int -> Int -> Int
relocValue HiAbs _ = absHi
relocValue LoAbs _ = absLo
relocValue HiPcrel pc = pcrelHi pc
relocValue LoPcrel pc = pcrelLo pc

-- | resolve a branch/jump/auipc operand: a bare expression is made PC-relative
resolveRelative :: SectionBases -> Int -> SymbolTable -> Operand -> Either LinkError Int
resolveRelative bases pc table op = case op of
  OpExpr e -> case foldConst e of
    Just v -> Right v
    Nothing -> subtract pc <$> evalExpr bases pc table e
  OpReloc k e -> relocValue k pc <$> evalExpr bases pc table e

resolveImm :: SectionBases -> Int -> SymbolTable -> Operand -> Either LinkError Int
resolveImm bases pc table op = case op of
  OpExpr e -> evalExpr bases pc table e
  OpReloc k e -> relocValue k pc <$> evalExpr bases pc table e

resolveOperand :: SectionBases -> Int -> SymbolTable -> SomeInstruction Operand -> Either LinkError (SomeInstruction Int)
resolveOperand bases pc table (SomeInstruction (JType op args)) = do
  v <- resolveRelative bases pc table (j_imm args)
  v' <- checkSigned "jump" 21 True (j_imm args) v
  return $ SomeInstruction $ JType op (args {j_imm = v'})
resolveOperand bases pc table (SomeInstruction (BType op args)) = do
  v <- resolveRelative bases pc table (b_imm args)
  v' <- checkSigned "branch" 13 True (b_imm args) v
  return $ SomeInstruction $ BType op (args {b_imm = v'})
resolveOperand bases pc table (SomeInstruction (UType AUIPC args)) = do
  v <- resolveRelative bases pc table (u_imm args)
  v' <- checkUpper (u_imm args) v
  return $ SomeInstruction $ UType AUIPC (args {u_imm = v'})
resolveOperand bases pc table (SomeInstruction (UType LUI args)) = do
  v <- resolveImm bases pc table (u_imm args)
  v' <- checkUpper (u_imm args) v
  return $ SomeInstruction $ UType LUI (args {u_imm = v'})
resolveOperand bases pc table (SomeInstruction (LoadI op args)) = do
  v <- resolveImm bases pc table (i_imm args)
  v' <- checkSigned "load offset" 12 False (i_imm args) v
  return $ SomeInstruction $ LoadI op (args {i_imm = v'})
resolveOperand bases pc table (SomeInstruction (JumpI op args)) = do
  v <- resolveImm bases pc table (i_imm args)
  v' <- checkSigned "jalr offset" 12 False (i_imm args) v
  return $ SomeInstruction $ JumpI op (args {i_imm = v'})
resolveOperand bases pc table (SomeInstruction (ArithI op args)) = do
  val <- resolveImm bases pc table (i_imm args)
  validVal <-
    if op `elem` [SLLI, SRLI, SRAI]
      then checkShiftBounds val
      else checkSigned "immediate" 12 False (i_imm args) val
  return $ SomeInstruction $ ArithI op (args {i_imm = validVal})
resolveOperand bases pc table (SomeInstruction (SType op args)) = do
  v <- resolveImm bases pc table (s_imm args)
  v' <- checkSigned "store offset" 12 False (s_imm args) v
  return $ SomeInstruction $ SType op (args {s_imm = v'})
resolveOperand bases pc table (SomeInstruction instr) =
  SomeInstruction <$> traverse (resolveImm bases pc table) instr
