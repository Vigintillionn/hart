module Linker where
import Types
import qualified Data.Map.Strict as M
import qualified Data.IntMap.Strict as IM
import Control.Monad (foldM)
import Control.Monad.State
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Bits (Bits(..))
import Machine
import Data.Word (Word8, Word32)
import Data.Char (ord)

type SymbolTable = M.Map String Int

data Executable = Executable 
    { execProgram :: Program
    , execDataMem :: IM.IntMap Word8
    , execSourceMap :: [(Word32, Int)]
    } deriving (Show)

instrSize :: SomeInstruction a -> Int
instrSize _ = 4

stmtSize :: Int -> Statement -> Int
stmtSize _ (StmtInstr i) = sum (map (const 4) (NE.toList $ lower i))
stmtSize _ (StmtDirective (DirSection _)) = 0
stmtSize _ (StmtDirective (DirString s))  = length s + 1
stmtSize _ (StmtDirective (DirAscii s))   = length s
stmtSize _ (StmtDirective (DirByte l))    = length l
stmtSize _ (StmtDirective (DirHalf l))    = length l * 2
stmtSize _ (StmtDirective (DirWord l))    = length l * 4
stmtSize _ (StmtDirective (DirSpace n))   = n
stmtSize pc (StmtDirective (DirAlign n))  =
    let alignVal = 2 ^ n
        remAlign = pc `mod` alignVal
    in if remAlign == 0 then 0 else alignVal - remAlign

lower :: ArchInstr 'Parsed -> NonEmpty (SomeInstruction Operand)
lower (RealInstr i) = i :| []
lower (PseudoInstr op) = case op of
    P_NOP -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (ImmVal 0))
    P_MV rd rs  -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (ImmVal 0))
    P_LI rd (ImmVal v)
        | v < -2048 || v > 2047 -> 
            let hi = (v + 0x800) `shiftR` 12
                lo = v .&. 0xFFF
            in SomeInstruction (UType LUI (UTypeArgs rd (ImmVal hi))) :|
               [ SomeInstruction (ArithI ADDI (ITypeArgs rd rd (ImmVal lo))) ]
    P_LI rd imm -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd x0 imm)
    P_NEG rd rs -> pure $ SomeInstruction $ RType SUB (RTypeArgs rd x0 rs)
    P_NOT rd rs -> pure $ SomeInstruction $ ArithI XORI (ITypeArgs rd rs (ImmVal (-1)))
    P_J off     -> pure $ SomeInstruction $ JType JAL (JTypeArgs x0 off)
    P_JR rs     -> pure $ SomeInstruction $ JumpI JALR (ITypeArgs x0 rs (ImmVal 0))
    P_RET       -> pure $ SomeInstruction $ JumpI JALR (ITypeArgs x0 x1 (ImmVal 0))
    P_LA rd lbl -> SomeInstruction (UType AUIPC (UTypeArgs rd (LabelHi lbl))) :|
                   [ SomeInstruction (ArithI ADDI (ITypeArgs rd rd (LabelLo lbl))) ]
    P_LOAD_GL lop rd lbl -> SomeInstruction (UType AUIPC (UTypeArgs rd (LabelHi lbl))) :|
                   [ SomeInstruction (LoadI lop (ITypeArgs rd rd (LabelLo lbl))) ]
    P_STORE_GL sop src lbl temp -> SomeInstruction (UType AUIPC (UTypeArgs temp (LabelHi lbl))) :|
                   [ SomeInstruction (SType sop (STypeArgs temp src (LabelLo lbl))) ]
    P_SEQZ rd rs -> pure $ SomeInstruction $ ArithI SLTIU (ITypeArgs rd rs (ImmVal 1))
    P_SNEZ rd rs -> pure $ SomeInstruction $ RType SLTU (RTypeArgs rd x0 rs)
    P_SLTZ rd rs -> pure $ SomeInstruction $ RType SLT  (RTypeArgs rd rs x0)
    P_SGTZ rd rs -> pure $ SomeInstruction $ RType SLT  (RTypeArgs rd x0 rs)
    P_BEQZ rs off -> pure $ SomeInstruction $ BType BEQ (BTypeArgs rs x0 off)
    P_BNEZ rs off -> pure $ SomeInstruction $ BType BNE (BTypeArgs rs x0 off)
    P_BLTZ rs off -> pure $ SomeInstruction $ BType BLT (BTypeArgs rs x0 off) -- rs < 0
    P_BGEZ rs off -> pure $ SomeInstruction $ BType BGE (BTypeArgs rs x0 off)
    P_BLEZ rs off -> pure $ SomeInstruction $ BType BGE (BTypeArgs x0 rs off)
    P_BGTZ rs off -> pure $ SomeInstruction $ BType BLT (BTypeArgs x0 rs off)
    P_BGT rs rt off  -> pure $ SomeInstruction $ BType BLT  (BTypeArgs rt rs off)
    P_BLE rs rt off  -> pure $ SomeInstruction $ BType BGE  (BTypeArgs rt rs off)
    P_BGTU rs rt off -> pure $ SomeInstruction $ BType BLTU (BTypeArgs rt rs off)
    P_BLEU rs rt off -> pure $ SomeInstruction $ BType BGEU (BTypeArgs rt rs off)
    P_CALL lbl -> SomeInstruction (UType AUIPC (UTypeArgs x1 (LabelHi lbl))) :|
                    [ SomeInstruction (JumpI JALR (ITypeArgs x1 x1 (LabelLo lbl))) ]
    P_TAIL lbl -> SomeInstruction (UType AUIPC (UTypeArgs x6 (LabelHi lbl))) :|
                    [ SomeInstruction (JumpI JALR (ITypeArgs x0 x6 (LabelLo lbl))) ]

expandProgram :: [(Int, ArchInstr 'Parsed)] -> [(Int, SomeInstruction Operand)]
expandProgram = concatMap (\(ln, instr) -> map (ln,) (NE.toList . lower $ instr))

data BuildState = BuildState
    { b_textPC :: Int
    , b_dataPC :: Int
    , b_section :: Section
    , b_table :: SymbolTable
    }

buildSymTable :: ParsedProgram -> Either String BuildState
buildSymTable = foldM step (BuildState 0 0x10000000 TextSection M.empty)
    where
        step st (_, (ml, ms)) = do
            let currentPC = if b_section st == TextSection then b_textPC st else b_dataPC st

            newTable <- case ml of
                Nothing -> Right (b_table st)
                Just n  -> if M.member n (b_table st)
                           then Left $ "Duplicate label: " ++ n
                           else Right $ M.insert n currentPC (b_table st)

            let st' = st { b_table = newTable }
            case ms of
                Nothing -> Right st'
                Just (StmtDirective (DirSection sec)) -> Right $ st' { b_section = sec }
                Just stmt -> do
                    let sz = stmtSize currentPC stmt
                    if b_section st == TextSection
                    then Right $ st' { b_textPC = b_textPC st' + sz }
                    else Right $ st' { b_dataPC = b_dataPC st' + sz }

data EmitState = EmitState
    { e_instrs  :: [(Int, ArchInstr 'Parsed)]
    , e_dataMem :: IM.IntMap Word8
    , e_textPC  :: Int
    , e_dataPC  :: Int
    , e_section :: Section
    }

emitSections :: ParsedProgram -> EmitState
emitSections = foldl step (EmitState [] IM.empty 0 0x10000000 TextSection)
  where
    step st (_, (_, Nothing)) = st
    step st (_, (_, Just (StmtDirective (DirSection sec)))) = st { e_section = sec }
    step st (ln, (_, Just stmt)) =
        let currentPC = if e_section st == TextSection then e_textPC st else e_dataPC st
            sz = stmtSize currentPC stmt
        in case stmt of
            StmtInstr i ->
                st { e_instrs = e_instrs st ++ [(ln, i)], e_textPC = e_textPC st + sz }
            StmtDirective dir ->
                let newMem = insertDirective currentPC dir (e_dataMem st)
                in st { e_dataMem = newMem, e_dataPC = e_dataPC st + sz }

    insertDirective :: Int -> Directive -> IM.IntMap Word8 -> IM.IntMap Word8
    insertDirective pc dir memMap = case dir of
        DirString s -> foldl (\m (i, c) -> IM.insert (pc + i) (fromIntegral $ ord c) m) memMap (zip [0..] (s ++ "\0"))
        DirAscii s  -> foldl (\m (i, c) -> IM.insert (pc + i) (fromIntegral $ ord c) m) memMap (zip [0..] s)
        DirByte xs  -> foldl (\m (i, x) -> IM.insert (pc + i) (fromIntegral x) m) memMap (zip [0..] xs)
        DirWord xs  -> foldl (\m (i, x) ->
                            let b0 = fromIntegral (x .&. 0xFF)
                                b1 = fromIntegral ((x `shiftR` 8) .&. 0xFF)
                                b2 = fromIntegral ((x `shiftR` 16) .&. 0xFF)
                                b3 = fromIntegral ((x `shiftR` 24) .&. 0xFF)
                            in IM.insert (pc + i*4 + 3) b3 $ IM.insert (pc + i*4 + 2) b2 $ IM.insert (pc + i*4 + 1) b1 $ IM.insert (pc + i*4) b0 m) memMap (zip [0..] xs)
        _ -> memMap

resolve :: ParsedProgram -> Either String Executable
resolve l = do
    buildState <- buildSymTable l
    let symTable = b_table buildState

    let emitted = emitSections l
    let rawInstrs = e_instrs emitted
    let expanded = expandProgram rawInstrs

    programWithLines <- evalStateT (mapM (\(ln, instr) -> do
        pc <- get
        resolved <- resolveInstruction symTable instr
        return (resolved, (fromIntegral pc :: Word32, ln))
        ) expanded) 0
        
    let program = map fst programWithLines
    let sourceMap = map snd programWithLines
    return $ Executable program (e_dataMem emitted) sourceMap

resolveImm :: String -> Operand -> Either String Int
resolveImm _ (ImmVal v) = Right v
resolveImm e _  = Left e

checkShiftBounds :: IArithOp -> Int -> Either String Int
checkShiftBounds op val
    | op `elem` [SLLI, SRLI, SRAI] && (val < 0 || val > 31) =
        Left $ "Shift amount out of range (0-31): " ++ show val
    | otherwise = Right val

resolveInstruction :: SymbolTable -> SomeInstruction Operand -> StateT Int (Either String) (SomeInstruction Int)
resolveInstruction table instr = do
    pc <- get
    resolved <- lift $ resolveOperand pc table instr
    modify (+4)
    return resolved

resolveRelative :: Int -> SymbolTable -> Operand -> Either String Int
resolveRelative _ _ (ImmVal v) = Right v
resolveRelative pc table (Label l) =
    case M.lookup l table of
        Just target -> Right $ target - pc
        Nothing     -> Left $ "Undefined label " ++ l
resolveRelative pc table (LabelHi l) =
    case M.lookup l table of
        Just target -> Right $ (target - pc + 0x800) `shiftR` 12
        Nothing     -> Left $ "Undefined label (Hi): " ++ l
resolveRelative pc table (LabelLo l) =
    case M.lookup l table of
        Just target -> Right $ (target - pc + 4) .&. 0xFFF
        Nothing     -> Left $ "Undefined label (Lo): " ++ l

resolveAbsolute :: SymbolTable -> Operand -> Either String Int
resolveAbsolute table (Label l) =
    case M.lookup l table of
        Just target -> Right target
        Nothing     -> Left $ "Undefined label: " ++ l
resolveAbsolute table (LabelHi l) =
    case M.lookup l table of
        Just target -> Right $ (target + 0x800) `shiftR` 12
        Nothing     -> Left $ "Undefined label (Hi): " ++ l
resolveAbsolute table (LabelLo l) =
    case M.lookup l table of
        Just target -> Right $ target .&. 0xFFF
        Nothing     -> Left $ "Undefined label (Lo): " ++ l
resolveAbsolute _ (ImmVal v) = Right v

resolveOperand :: Int -> SymbolTable -> SomeInstruction Operand -> Either String (SomeInstruction Int)
resolveOperand pc table (SomeInstruction (JType op args))
    = SomeInstruction . JType op <$> traverse (resolveRelative pc table) args
resolveOperand pc table (SomeInstruction (BType op args))
    = SomeInstruction . BType op <$> traverse (resolveRelative pc table) args
resolveOperand pc table (SomeInstruction (UType AUIPC args))
    = SomeInstruction . UType AUIPC <$> traverse (resolveRelative pc table) args
resolveOperand pc table (SomeInstruction (LoadI op args)) =
    SomeInstruction . LoadI op <$> traverse (resolveRelative pc table) args
resolveOperand pc table (SomeInstruction (JumpI op args)) =
    SomeInstruction . JumpI op <$> traverse (resolveRelative pc table) args
resolveOperand pc table (SomeInstruction (ArithI op args)) = do
    val <- resolveRelative pc table (i_imm args)
    validVal <- checkShiftBounds op val
    return $ SomeInstruction $ ArithI op (args { i_imm = validVal })
resolveOperand pc table (SomeInstruction (SType op args)) =
    SomeInstruction . SType op <$> traverse (resolveRelative pc table) args
resolveOperand _ table (SomeInstruction instr) =
    SomeInstruction <$> traverse (resolveAbsolute table) instr
