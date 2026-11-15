module Linker
  ( Executable (..),
    Symbol (..),
    SymType (..),
    SymBinding (..),
    EntryPolicy (..),
    resolve,
    resolveWith,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (foldM, unless, when, (>=>))
import Control.Monad.State.Strict (StateT, execStateT, get, gets, lift, modify')
import Data.Bifunctor (first)
import Data.Bits (Bits (..))
import Data.Char (ord)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as M
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Set qualified as S
import Data.Word (Word32, Word8)
import Error (LinkError (..))
import Loc (Loc, locFile, locLine, locUnit)
import Machine
import Types

-- | a translation unit: the root buffer a line belongs to. Lines pulled in by
-- @.include@ carry the unit of the file that included them.
type Unit = FilePath

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

-- | symbol definitions: 'Local' symbols are visible only inside their unit,
-- 'Global' and 'Weak' ones everywhere. An exported symbol remembers its
-- defining unit so a deferred constant evaluates in the right scope.
data Symbols = Symbols
  { symLocals :: !(M.Map (Unit, String) Symbol),
    symGlobals :: !(M.Map String (Unit, Symbol))
  }

emptySymbols :: Symbols
emptySymbols = Symbols M.empty M.empty

insertLocal :: (Unit, String) -> Symbol -> Symbols -> Symbols
insertLocal key sym syms = syms {symLocals = M.insert key sym (symLocals syms)}

insertGlobal :: String -> (Unit, Symbol) -> Symbols -> Symbols
insertGlobal name entry syms = syms {symGlobals = M.insert name entry (symGlobals syms)}

-- | a unit's own symbols shadow same-named globals from elsewhere
lookupSym :: Symbols -> Unit -> String -> Maybe (Unit, Symbol)
lookupSym syms unit name =
  ((unit,) <$> M.lookup (unit, name) (symLocals syms))
    <|> M.lookup name (symGlobals syms)

-- | every name each unit defines itself (labels, constants, commons)
collectOwnDefs :: ParsedProgram -> S.Set (Unit, String)
collectOwnDefs prog =
  S.fromList [(locUnit loc, name) | (loc, (mLabel, mStmt)) <- prog, name <- defined mLabel mStmt]
  where
    defined mLabel mStmt = maybe [] pure mLabel ++ maybe [] stmtDef mStmt
    stmtDef (StmtDirective (DirEqu name _)) = [name]
    stmtDef (StmtDirective (DirEquiv name _)) = [name]
    stmtDef (StmtDirective (DirComm _ name _ _)) = [name]
    stmtDef _ = []

-- | bindings declared with @.globl@/@.local@/@.weak@, per (unit, symbol).
-- Collected before placement so a declaration after its label still applies;
-- the last declaration for a name wins.
type Bindings = M.Map (Unit, String) SymBinding

collectBindings :: ParsedProgram -> Bindings
collectBindings prog =
  M.fromList
    [ ((locUnit loc, name), bind)
      | (loc, (_, Just (StmtDirective dir))) <- prog,
        (bind, names) <- declared dir,
        name <- names
    ]
  where
    declared (DirGlobl ns) = [(Global, ns)]
    declared (DirLocal ns) = [(Local, ns)]
    declared (DirWeak ns) = [(Weak, ns)]
    declared _ = []

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

-- | everything expression evaluation needs once placement is finished
data LinkEnv = LinkEnv
  { envBases :: !SectionBases,
    envSyms :: !Symbols,
    -- | target expression (with its unit scope) of every placed
    -- @auipc %pcrel_hi@, keyed by its address; consulted by @%pcrel_lo@
    envPcrelHi :: !(M.Map Int (Unit, Expr)),
    -- | names a unit defines itself but has not reached yet. Until it does,
    -- another unit's export of the same name must not stand in for it, or the
    -- result would depend on link order. Empty once placement is finished.
    envPending :: !(S.Set (Unit, String))
  }

-- | the definition of @name@ that a reference in @unit@ binds to right now
visibleSym :: LinkEnv -> Unit -> String -> Maybe (Unit, Symbol)
visibleSym env unit name = case lookupSym (envSyms env) unit name of
  Just (defUnit, _) | defUnit /= unit, S.member (unit, name) (envPending env) -> Nothing
  found -> found

data Executable = Executable
  { execProgram :: Program,
    execDataMem :: IM.IntMap Word8,
    -- | per-instruction provenance: (load address, source line, source file)
    execSourceMap :: [(Word32, Int, FilePath)],
    -- | the resolved entry symbol (@_start@, else @main@, looked up among the
    -- exported globals) and its address; 'Nothing' means start at 'entryPoint'
    execEntry :: Maybe (String, Word32)
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

-- | reinterpret the low 32 bits of a value as signed, so @0xFFFFFFFF@ is @-1@
toSigned32 :: Int -> Int
toSigned32 v = ((v + bit 31) .&. 0xFFFFFFFF) - bit 31

lower :: ArchInstr 'Parsed -> NonEmpty (SomeInstruction Operand)
lower (RealInstr i) = i :| []
lower (PseudoInstr op) = case op of
  P_NOP -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (litOp 0))
  P_MV rd rs -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (litOp 0))
  P_LI rd imm -> case imm of
    -- a constant we can fold now: emit the size-optimal form
    OpExpr e
      | Just v <- toSigned32 <$> foldConst e ->
          if v < -2048 || v > 2047
            then
              let (hi, lo) = hiLo12 v
               in SomeInstruction (UType LUI (UTypeArgs rd (litOp (hi .&. 0xFFFFF))))
                    :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (litOp lo)))]
            else pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd x0 (litOp v))
    -- a symbol/expression whose value is unknown at lowering: emit the worst case (lui+addi)
    OpExpr e ->
      SomeInstruction (UType LUI (UTypeArgs rd (OpReloc HiAbs e)))
        :| [SomeInstruction (ArithI ADDI (ITypeArgs rd rd (OpReloc LoAbs e)))]
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

maxAlignExponent :: Int
maxAlignExponent = 31

-- | the byte alignment an alignment directive's argument denotes; the argument is assumed non-negative
alignBytes :: AlignMode -> Int -> Either LinkError Int
alignBytes AlignPow2 e
  | e > maxAlignExponent = Left (ImmOutOfRange (alignCtx AlignPow2) 0 maxAlignExponent e)
  | otherwise = Right (bit e)
alignBytes AlignBytes n
  | n > 1, popCount n /= 1 = Left (AlignNotPowerOfTwo n)
  | otherwise = Right n

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
    -- | declared bindings, collected from the whole program before the walk
    pBinds :: !Bindings,
    -- | every name each unit defines itself, collected before the walk
    pOwnDefs :: !(S.Set (Unit, String)),
    -- | the unit being walked
    pUnit :: !(Maybe Unit),
    -- | every size and alignment evaluated so far, in reverse order. The two
    -- walks must agree on them, or the measured layout is not the real one.
    pLayoutVals :: ![(Loc, Int)],
    -- | current byte offset within each visited section
    pOffsets :: !(M.Map Section Int),
    -- | the strongest alignment (in bytes) requested within each section
    pAligns :: !(M.Map Section Int),
    -- | visited sections in reverse first-seen order (reversed when read), used to lay out each region
    pOrder :: ![Section],
    pCur :: !Section,
    pSyms :: !Symbols,
    -- | every (unit, name) defined so far, to reject a same-unit redefinition
    pDefined :: !(S.Set (Unit, String)),
    -- | the subset that may not even be redefined by @.equ@/@.set@ (labels and @.equiv@ constants)
    pLocked :: !(S.Set (Unit, String)),
    -- | expanded instructions in reverse order: (address, source loc, instr)
    pInstrs :: ![(Int, Loc, SomeInstruction Operand)],
    -- | emitting data directives in reverse order: (address, source loc, section, dir),
    -- their bytes are produced in a second pass, once every symbol is known, so
    -- that data may reference forward symbols (e.g. @.word later_label@)
    pDataDirs :: ![(Int, Loc, Section, Directive)]
  }

initPlace :: Bindings -> S.Set (Unit, String) -> SectionBases -> Place
initPlace binds ownDefs bases =
  Place
    { pBases = bases,
      pBinds = binds,
      pOwnDefs = ownDefs,
      pUnit = Nothing,
      pLayoutVals = [],
      pOffsets = M.singleton textSection 0,
      pAligns = M.empty,
      pOrder = [textSection],
      pCur = textSection,
      pSyms = emptySymbols,
      pDefined = S.empty,
      pLocked = S.empty,
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

-- | define a symbol under its declared binding (the 'symBinding' on the given
-- symbol is the default when none was declared). Local symbols go into their
-- unit's scope; global and weak ones are exported.
defineSym :: Loc -> String -> Bool -> Symbol -> PlaceM ()
defineSym loc name redefinable sym = do
  let unit = locUnit loc
      key = (unit, name)
  p <- get
  let taken = S.member key (if redefinable then pLocked p else pDefined p)
  when taken $ throw (LocatedLink loc (DuplicateLabel name))
  let sym' = sym {symBinding = M.findWithDefault (symBinding sym) key (pBinds p)}
  modify' $ \q ->
    q
      { pDefined = S.insert key (pDefined q),
        pLocked = (if redefinable then id else S.insert key) (pLocked q)
      }
  case symBinding sym' of
    Local -> modify' $ \q -> q {pSyms = insertLocal key sym' (pSyms q)}
    _ -> exportSym loc unit name sym'

-- | export a global or weak definition: a strong definition beats a weak one,
-- the first weak definition wins otherwise, and two strong definitions from
-- different units collide (a same-unit redefinition is a redefinable constant,
-- already vetted by 'defineSym')
exportSym :: Loc -> Unit -> String -> Symbol -> PlaceM ()
exportSym loc unit name sym = do
  existing <- gets (M.lookup name . symGlobals . pSyms)
  case existing of
    Just (defUnit, old)
      | defUnit /= unit, strong old, strong sym ->
          throw (LocatedLink loc (MultipleDefinition name))
      | defUnit /= unit, not (strong sym) -> pure ()
    _ -> modify' $ \p -> p {pSyms = insertGlobal name (unit, sym) (pSyms p)}
  where
    strong s = symBinding s == Global

defLabel :: Loc -> String -> PlaceM ()
defLabel loc name = do
  p <- get
  defineSym loc name False (Symbol (Just (pCur p)) (curOffset p) AddrSym Local)

-- | reserve a @.comm@/@.lcomm@ common symbol, does not change the current
-- section. Deliberately no ld-style merging of same-named commons: a name
-- exported strongly twice is a 'MultipleDefinition', per the one-definition rule.
reserveCommon :: Loc -> Bool -> String -> Int -> Int -> PlaceM ()
reserveCommon loc isLocal name size align = do
  let a = max 1 align
      bind = if isLocal then Local else Global
  modify' (noteAlign commonSection a . visitSection commonSection)
  aligned <- gets (alignUp a . offsetOf commonSection)
  defineSym loc name False (Symbol (Just commonSection) aligned AddrSym bind)
  modify' $ \p -> p {pOffsets = M.insert commonSection (aligned + size) (pOffsets p)}

-- | replace the location counter @.@ in an expression with a literal
substCur :: Int -> Expr -> Expr
substCur loc = go
  where
    go ECur = EInt loc
    go (EUn o e) = EUn o (go e)
    go (EBin o a b) = EBin o (go a) (go b)
    go e = e

-- | freeze every constant an expression names at its current value, so a use
-- sees the @.set@ in force where it appears rather than the last one
snapshotConsts :: LinkEnv -> Unit -> Expr -> Expr
snapshotConsts env unit = go
  where
    go (ESym s)
      | Just (_, Symbol {symType = ConstSym, symValue = v}) <- visibleSym env unit s = ESnapshot s v
    go (EUn o e) = EUn o (go e)
    go (EBin o a b) = EBin o (go a) (go b)
    go e = e

mapOperandExpr :: (Expr -> Expr) -> Operand -> Operand
mapOperandExpr f (OpExpr e) = OpExpr (f e)
mapOperandExpr f (OpReloc k e) = OpReloc k (f e)

mapDataExprs :: (Expr -> Expr) -> Directive -> Directive
mapDataExprs f dir = case dir of
  DirByte es -> DirByte (map f es)
  DirHalf es -> DirHalf (map f es)
  DirWord es -> DirWord (map f es)
  _ -> dir

-- | the symbols visible at this point of the walk
layoutEnv :: Place -> LinkEnv
layoutEnv p =
  -- layout-time evaluation never sees a %pcrel operand, so no index is needed
  LinkEnv (pBases p) (pSyms p) M.empty (pOwnDefs p `S.difference` pDefined p)

-- | each root file starts in @.text@, at a word boundary in every section, as
-- if it had been assembled on its own
enterUnit :: Unit -> PlaceM ()
enterUnit unit = do
  current <- gets pUnit
  unless (current == Just unit) $
    modify' $ \p ->
      p
        { pUnit = Just unit,
          pCur = textSection,
          pOffsets = M.map (alignUp sectionAlign) (pOffsets p)
        }

placeStep :: (Loc, SourceLine) -> PlaceM ()
placeStep (loc, (mLabel, mStmt)) = do
  enterUnit (locUnit loc)
  mapM_ (defLabel loc) mLabel
  here <- gets placeAddr
  mapM_ (placeStmt loc here) mStmt

placeStmt :: Loc -> Int -> Statement -> PlaceM ()
placeStmt loc here stmt = case stmt of
  StmtDirective (DirSection sec) -> modify' (setSection sec)
  StmtDirective (DirEqu name e) -> defineConst True name e
  StmtDirective (DirEquiv name e) -> defineConst False name e
  -- bindings were collected before the walk
  StmtDirective (DirGlobl _) -> pure ()
  StmtDirective (DirLocal _) -> pure ()
  StmtDirective (DirWeak _) -> pure ()
  StmtDirective (DirSpace e) -> do
    n <- layoutVal e >>= requireNonNeg ".space size"
    advance n
  StmtDirective (DirAlign mode e) -> do
    v <- layoutVal e >>= requireNonNeg (alignCtx mode)
    a <- lift (atLoc loc (alignBytes mode v))
    cur <- gets pCur
    modify' (noteAlign cur a)
    advance (padTo a here)
  StmtDirective (DirComm isLocal name sizeE mAlignE) -> do
    size <- layoutVal sizeE >>= requireNonNeg ".comm size"
    align <- maybe (pure (defaultCommAlign size)) (layoutVal >=> requireNonNeg ".comm alignment") mAlignE
    reserveCommon loc isLocal name size align
  StmtDirective dir -> do
    snap <- snapshot
    modify' $ \p -> p {pDataDirs = (here, loc, pCur p, mapDataExprs snap dir) : pDataDirs p}
    advance (dataSize dir)
  StmtInstr i -> do
    snap <- snapshot
    let subs = NE.toList (lower i)
        frozen (SomeInstruction sub) = SomeInstruction (mapOperandExpr snap <$> sub)
        placed = zipWith (\k sub -> (here + 4 * k, loc, frozen sub)) [0 ..] subs
    modify' $ \p -> p {pInstrs = reverse placed ++ pInstrs p}
    advance (4 * length subs)
  where
    snapshot = gets (\p -> snapshotConsts (layoutEnv p) (locUnit loc))
    layoutVal e = do
      p <- get
      v <- lift (atLoc loc (evalExpr (layoutEnv p) (locUnit loc) here e))
      modify' $ \q -> q {pLayoutVals = (loc, v) : pLayoutVals q}
      pure v
    requireNonNeg ctx v
      | v < 0 = throw (LocatedLink loc (NegativeValue ctx v))
      | otherwise = pure v
    -- a constant is evaluated eagerly when every symbol it names is already defined
    defineConst redefinable name e0 = do
      p <- get
      let e = snapshotConsts (layoutEnv p) (locUnit loc) (substCur here e0)
      case evalExpr (layoutEnv p) (locUnit loc) here e of
        Right v -> defineSym loc name redefinable (Symbol Nothing v ConstSym Local)
        Left (UndefinedLabel _) ->
          defineSym loc name redefinable (Symbol Nothing 0 (DeferredSym e) Local)
        Left err -> throw (LocatedLink loc err)

-- | The @n@ little-endian bytes of @x@
leBytes :: Int -> Int -> [Word8]
leBytes n x = [fromIntegral ((x `shiftR` (8 * k)) .&. 0xFF) | k <- [0 .. n - 1]]

emitDirective :: LinkEnv -> Unit -> Int -> Directive -> Either LinkError [(Int, Word8)]
emitDirective env unit base dir = case dir of
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
          v <- evalExpr env unit addr e
          if v < lo || v > hi
            then Left (ImmOutOfRange ctx lo hi v)
            else Right (zip [addr ..] (leBytes width v))

-- | an undefined symbol declared @.weak@ resolves to 0, per ELF semantics
weakStubs :: Bindings -> Symbols -> Symbols
weakStubs binds syms = foldl' add syms (M.toList binds)
  where
    add acc ((unit, name), Weak)
      | Nothing <- lookupSym acc unit name =
          insertLocal (unit, name) (Symbol Nothing 0 ConstSym Weak) acc
    add acc _ = acc

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

-- | reject a layout whose text spills into the data region or whose data/bss
-- reaches the heap
checkRegions :: M.Map Section Int -> SectionBases -> Either LinkError ()
checkRegions sizes bases = do
  check "text" (endOf ((== SecText) . secClass)) dataBase
  check "data" (endOf ((/= SecText) . secClass)) (fromIntegral heapBase)
  where
    endOf inRegion =
      maximum (0 : [base + M.findWithDefault 0 sec sizes | (sec, base) <- M.toList bases, inRegion sec])
    check region end limit
      | end > limit = Left (RegionOverflow region end limit)
      | otherwise = Right ()

-- | the entry symbol: @_start@, else @main@, looked up among the exported globals
entrySymbol :: SectionBases -> Symbols -> Maybe (String, Word32)
entrySymbol bases syms =
  listToMaybe
    [ (name, fromIntegral (symAbsolute bases sym))
      | name <- ["_start", "main"],
        Just (_, sym) <- [M.lookup name (symGlobals syms)]
    ]

-- | what to do with a build that exports neither @_start@ nor @main@
data EntryPolicy
  = -- | start at 'entryPoint'
    FallBackToZero
  | -- | fail with 'NoEntrySymbol'
    RequireEntry
  deriving (Show, Eq)

resolve :: ParsedProgram -> Either LinkError Executable
resolve = resolveWith FallBackToZero

resolveWith :: EntryPolicy -> ParsedProgram -> Either LinkError Executable
resolveWith policy prog = do
  -- walk with every section at base 0 purely to measure sizes
  measured <- execStateT walk (initPlace binds ownDefs M.empty)
  let sizes = pOffsets measured
      bases = assignBases sizes (pAligns measured) (reverse (pOrder measured))
  checkRegions sizes bases
  -- walk again with real bases, so every recorded address, and any @.equ@ referencing a label, is already absolute
  placed <- execStateT walk (initPlace binds ownDefs bases)
  checkStableLayout measured placed
  let instrs = reverse (pInstrs placed)
      syms = weakStubs binds (pSyms placed)
      env = LinkEnv bases syms (pcrelHiIndex instrs) S.empty
      entry = entrySymbol bases syms
  when (policy == RequireEntry && null entry) $ Left NoEntrySymbol
  dataMem <- foldM (emitInto env) IM.empty (reverse (pDataDirs placed))
  resolved <- traverse (resolveOne env) instrs
  return $ Executable (map fst resolved) dataMem (map snd resolved) entry
  where
    binds = collectBindings prog
    ownDefs = collectOwnDefs prog
    walk = mapM_ placeStep prog
    emitInto env mem (addr, loc, sec, dir) = do
      bytes <- atLoc loc (emitDirective env (locUnit loc) addr dir)
      -- bss is NOBITS: its directives are still evaluated, but carry no bytes
      Right $
        if secClass sec == SecBss
          then mem
          else foldl' (\m (a, b) -> IM.insert a b m) mem bytes
    resolveOne env (addr, loc, instr) =
      atLoc loc $ do
        r <- resolveInstr env (locUnit loc) addr instr
        return (r, (fromIntegral addr, locLine loc, locFile loc))

-- | the measuring walk ran with every section at base 0. A size or alignment
-- that came out differently with the real bases depends on an address, and the
-- bases were assigned from sizes that are no longer true.
checkStableLayout :: Place -> Place -> Either LinkError ()
checkStableLayout measured placed =
  maybe (Right ()) Left . listToMaybe . mapMaybe unstable $
    zip (reverse (pLayoutVals measured)) (reverse (pLayoutVals placed))
  where
    unstable ((_, before), (loc, after))
      | before /= after = Just (LocatedLink loc AddressDependentLayout)
      | otherwise = Nothing

pcrelHiIndex :: [(Int, Loc, SomeInstruction Operand)] -> M.Map Int (Unit, Expr)
pcrelHiIndex instrs =
  M.fromList
    [ (addr, (locUnit loc, e))
      | (addr, loc, SomeInstruction (UType AUIPC args)) <- instrs,
        OpReloc HiPcrel e <- [u_imm args]
    ]

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

evalExpr :: LinkEnv -> Unit -> Int -> Expr -> Either LinkError Int
evalExpr env unit0 here = go S.empty unit0
  where
    -- @seen@ is the set of deferred constants currently being resolved, so a
    -- constant that refers back to itself is reported rather than looping
    go _ _ (EInt n) = Right n
    go _ _ ECur = Right here
    go _ _ (ESnapshot _ v) = Right v
    go seen unit (ESym s) = resolveSym seen unit s
    go seen unit (EUn o e) = applyUnOp o <$> go seen unit e
    go seen unit (EBin o a b) = do
      x <- go seen unit a
      y <- go seen unit b
      maybe (Left DivByZero) Right (applyBinOp o x y)
    resolveSym seen unit s = case visibleSym env unit s of
      Nothing -> Left (UndefinedLabel s)
      Just (defUnit, sym) -> case symType sym of
        -- a deferred constant evaluates in the scope of the unit that defined it
        DeferredSym e
          | S.member (defUnit, s) seen -> Left (CircularConstant s)
          | otherwise -> go (S.insert (defUnit, s) seen) defUnit e
        _ -> Right (symAbsolute (envBases env) sym)

pcrelHi, pcrelLo :: Int -> Int -> Int
pcrelHi pc t = fst (hiLo12 (t - pc))
pcrelLo pc t = snd (hiLo12 (t - pc + 4))

-- the hi part is masked to its 20-bit field, so an unsigned value with the
-- top bit set reads as that field rather than as bit 20 spilling over
absHi, absLo :: Int -> Int
absHi v = fst (hiLo12 v) .&. 0xFFFFF
absLo = snd . hiLo12

-- | an absolute relocation splits a 32-bit value, written signed or unsigned
checkWord :: Int -> Either LinkError Int
checkWord v
  | v < lo || v > hi = Left (ImmOutOfRange "32-bit value" lo hi v)
  | otherwise = Right v
  where
    lo = negate (bit 31)
    hi = bit 32 - 1

resolveReloc :: LinkEnv -> Unit -> Int -> RelocKind -> Expr -> Either LinkError Int
resolveReloc env unit pc kind e = case kind of
  HiAbs -> absHi <$> (value >>= checkWord)
  LoAbs -> absLo <$> (value >>= checkWord)
  HiPcrel -> pcrelHi pc <$> value
  LoPcrel -> pcrelLo pc <$> value
  -- the expression names the label of the paired auipc; the low bits come
  -- from that auipc's own target and pc
  LoPcrelRef -> do
    site <- value
    case M.lookup site (envPcrelHi env) of
      Nothing -> Left (MissingPcrelHi site)
      Just (siteUnit, targetE) -> do
        target <- evalExpr env siteUnit site targetE
        Right (snd (hiLo12 (target - site)))
  where
    value = evalExpr env unit pc e

-- | resolve a branch/jump/auipc operand: a bare expression is made PC-relative
resolveRelative :: LinkEnv -> Unit -> Int -> Operand -> Either LinkError Int
resolveRelative env unit pc op = case op of
  OpExpr e -> case foldConst e of
    Just v -> Right v
    Nothing -> subtract pc <$> evalExpr env unit pc e
  OpReloc k e -> resolveReloc env unit pc k e

resolveImm :: LinkEnv -> Unit -> Int -> Operand -> Either LinkError Int
resolveImm env unit pc op = case op of
  OpExpr e -> evalExpr env unit pc e
  OpReloc k e -> resolveReloc env unit pc k e

resolveInstr :: LinkEnv -> Unit -> Int -> SomeInstruction Operand -> Either LinkError (SomeInstruction Int)
resolveInstr env unit pc (SomeInstruction instr) = case instr of
  JType op args -> do
    v <- rel (j_imm args) >>= checkSigned "jump" 21 True (j_imm args)
    pure $ SomeInstruction $ JType op args {j_imm = v}
  BType op args -> do
    v <- rel (b_imm args) >>= checkSigned "branch" 13 True (b_imm args)
    pure $ SomeInstruction $ BType op args {b_imm = v}
  UType AUIPC args -> do
    v <- rel (u_imm args) >>= checkUpper (u_imm args)
    pure $ SomeInstruction $ UType AUIPC args {u_imm = v}
  UType LUI args -> do
    v <- imm (u_imm args) >>= checkUpper (u_imm args)
    pure $ SomeInstruction $ UType LUI args {u_imm = v}
  LoadI op args -> do
    v <- imm (i_imm args) >>= checkSigned "load offset" 12 False (i_imm args)
    pure $ SomeInstruction $ LoadI op args {i_imm = v}
  JumpI op args -> do
    v <- imm (i_imm args) >>= checkSigned "jalr offset" 12 False (i_imm args)
    pure $ SomeInstruction $ JumpI op args {i_imm = v}
  ArithI op args -> do
    v <- imm (i_imm args)
    v' <-
      if op `elem` [SLLI, SRLI, SRAI]
        then checkShiftBounds v
        else checkSigned "immediate" 12 False (i_imm args) v
    pure $ SomeInstruction $ ArithI op args {i_imm = v'}
  SType op args -> do
    v <- imm (s_imm args) >>= checkSigned "store offset" 12 False (s_imm args)
    pure $ SomeInstruction $ SType op args {s_imm = v}
  _ -> SomeInstruction <$> traverse imm instr
  where
    rel = resolveRelative env unit pc
    imm = resolveImm env unit pc
