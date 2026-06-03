module Linker (Executable (..), resolve) where

import Control.Monad (foldM)
import Control.Monad.State
import Data.Bifunctor (first)
import Data.Bits (Bits (..))
import Data.Char (ord)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl', mapAccumL)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as M
import Data.Word (Word32, Word8)
import Error (LinkError (..))
import Machine
import Types

type SymbolTable = M.Map String Int

data Executable = Executable
  { execProgram :: Program,
    execDataMem :: IM.IntMap Word8,
    execSourceMap :: [(Word32, Int)]
  }
  deriving (Show)

instrSize :: SomeInstruction a -> Int
instrSize _ = 4

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

lower :: ArchInstr 'Parsed -> NonEmpty (SomeInstruction Operand)
lower (RealInstr i) = i :| []
lower (PseudoInstr op) = case op of
  P_NOP -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (ImmVal 0))
  P_MV rd rs -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (ImmVal 0))
  P_LI rd (ImmVal v)
    | v < -2048 || v > 2047 ->
        let hi = (v + 0x800) `shiftR` 12
            lo = v .&. 0xFFF
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

expandProgram :: [(Int, ArchInstr 'Parsed)] -> [(Int, SomeInstruction Operand)]
expandProgram = concatMap (\(ln, instr) -> map (ln,) (NE.toList . lower $ instr))

dataBase :: Int
dataBase = 0x10000000

data Layout = Layout
  { l_textPC :: !Int,
    l_dataPC :: !Int,
    l_section :: !Section
  }

initLayout :: Layout
initLayout = Layout 0 dataBase TextSection

layoutPC :: Layout -> Int
layoutPC l = if l_section l == TextSection then l_textPC l else l_dataPC l

stepLayout :: Layout -> Maybe Statement -> (Int, Layout)
stepLayout lay ms = case ms of
  Nothing -> (here, lay)
  Just (StmtDirective (DirSection sec)) -> (here, lay {l_section = sec})
  Just stmt ->
    let sz = stmtSize here stmt
        lay'
          | l_section lay == TextSection = lay {l_textPC = l_textPC lay + sz}
          | otherwise = lay {l_dataPC = l_dataPC lay + sz}
     in (here, lay')
  where
    here = layoutPC lay

layout :: ParsedProgram -> [(Int, Int, SourceLine)]
layout = snd . mapAccumL step initLayout
  where
    step lay (ln, sl@(_, ms)) =
      let (here, lay') = stepLayout lay ms
       in (lay', (ln, here, sl))

buildSymTable :: ParsedProgram -> Either LinkError SymbolTable
buildSymTable = foldM step M.empty . layout
  where
    step tbl (ln, here, (ml, _)) = case ml of
      Nothing -> Right tbl
      Just n
        | M.member n tbl -> Left (LocatedLink ln (DuplicateLabel n))
        | otherwise -> Right (M.insert n here tbl)

emitSections :: ParsedProgram -> ([(Int, ArchInstr 'Parsed)], IM.IntMap Word8)
emitSections prog = (reverse instrs, dataMem)
  where
    (instrs, dataMem) = foldl' step ([], IM.empty) (layout prog)
    step acc@(is, dm) (ln, here, (_, ms)) = case ms of
      Just (StmtInstr i) -> ((ln, i) : is, dm)
      Just (StmtDirective dir) -> (is, insertDirective here dir dm)
      _ -> acc

    insertDirective :: Int -> Directive -> IM.IntMap Word8 -> IM.IntMap Word8
    insertDirective pc dir memMap = case dir of
      DirString s -> foldl' (\m (i, c) -> IM.insert (pc + i) (fromIntegral $ ord c) m) memMap (zip [0 ..] (s ++ "\0"))
      DirAscii s -> foldl' (\m (i, c) -> IM.insert (pc + i) (fromIntegral $ ord c) m) memMap (zip [0 ..] s)
      DirByte xs -> foldl' (\m (i, x) -> IM.insert (pc + i) (fromIntegral x) m) memMap (zip [0 ..] xs)
      DirWord xs ->
        foldl'
          ( \m (i, x) ->
              let b0 = fromIntegral (x .&. 0xFF)
                  b1 = fromIntegral ((x `shiftR` 8) .&. 0xFF)
                  b2 = fromIntegral ((x `shiftR` 16) .&. 0xFF)
                  b3 = fromIntegral ((x `shiftR` 24) .&. 0xFF)
               in IM.insert (pc + i * 4 + 3) b3 $ IM.insert (pc + i * 4 + 2) b2 $ IM.insert (pc + i * 4 + 1) b1 $ IM.insert (pc + i * 4) b0 m
          )
          memMap
          (zip [0 ..] xs)
      _ -> memMap

resolve :: ParsedProgram -> Either LinkError Executable
resolve l = do
  symTable <- buildSymTable l

  let (rawInstrs, dataMem) = emitSections l
  let expanded = expandProgram rawInstrs

  programWithLines <-
    evalStateT
      ( mapM
          ( \(ln, instr) -> do
              pc <- get
              resolved <- mapStateT (first (LocatedLink ln)) (resolveInstruction symTable instr)
              return (resolved, (fromIntegral pc :: Word32, ln))
          )
          expanded
      )
      0

  let program = map fst programWithLines
  let sourceMap = map snd programWithLines
  return $ Executable program dataMem sourceMap

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

resolveInstruction :: SymbolTable -> SomeInstruction Operand -> StateT Int (Either LinkError) (SomeInstruction Int)
resolveInstruction table instr = do
  pc <- get
  resolved <- lift $ resolveOperand pc table instr
  modify (+ 4)
  return resolved

resolveRelative :: Int -> SymbolTable -> Operand -> Either LinkError Int
resolveRelative _ _ (ImmVal v) = Right v
resolveRelative pc table (Label l) =
  case M.lookup l table of
    Just target -> Right $ target - pc
    Nothing -> Left (UndefinedLabel l)
resolveRelative pc table (LabelHi l) =
  case M.lookup l table of
    Just target -> Right $ (target - pc + 0x800) `shiftR` 12
    Nothing -> Left (UndefinedLabel l)
resolveRelative pc table (LabelLo l) =
  case M.lookup l table of
    Just target -> Right $ (target - pc + 4) .&. 0xFFF
    Nothing -> Left (UndefinedLabel l)

resolveAbsolute :: SymbolTable -> Operand -> Either LinkError Int
resolveAbsolute table (Label l) =
  case M.lookup l table of
    Just target -> Right target
    Nothing -> Left (UndefinedLabel l)
resolveAbsolute table (LabelHi l) =
  case M.lookup l table of
    Just target -> Right $ (target + 0x800) `shiftR` 12
    Nothing -> Left (UndefinedLabel l)
resolveAbsolute table (LabelLo l) =
  case M.lookup l table of
    Just target -> Right $ target .&. 0xFFF
    Nothing -> Left (UndefinedLabel l)
resolveAbsolute _ (ImmVal v) = Right v

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
  v <- resolveRelative pc table (i_imm args)
  v' <- checkSigned "load offset" 12 False (i_imm args) v
  return $ SomeInstruction $ LoadI op (args {i_imm = v'})
resolveOperand pc table (SomeInstruction (JumpI op args)) = do
  v <- resolveRelative pc table (i_imm args)
  v' <- checkSigned "jalr offset" 12 False (i_imm args) v
  return $ SomeInstruction $ JumpI op (args {i_imm = v'})
resolveOperand pc table (SomeInstruction (ArithI op args)) = do
  val <- resolveRelative pc table (i_imm args)
  validVal <-
    if op `elem` [SLLI, SRLI, SRAI]
      then checkShiftBounds op val
      else checkSigned "immediate" 12 False (i_imm args) val
  return $ SomeInstruction $ ArithI op (args {i_imm = validVal})
resolveOperand pc table (SomeInstruction (SType op args)) = do
  v <- resolveRelative pc table (s_imm args)
  v' <- checkSigned "store offset" 12 False (s_imm args) v
  return $ SomeInstruction $ SType op (args {s_imm = v'})
resolveOperand _ table (SomeInstruction instr) =
  SomeInstruction <$> traverse (resolveAbsolute table) instr
