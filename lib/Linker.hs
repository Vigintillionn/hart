module Linker where
import Types 
import qualified Data.Map.Strict as M
import Control.Monad (foldM)
import Control.Monad.State
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Bits (Bits(..))

type SymbolTable = M.Map String Int

instrSize :: SomeInstruction a -> Int
instrSize _ = 4

lower :: ArchInstr 'Parsed -> NonEmpty (SomeInstruction Operand)
lower (RealInstr i) = i :| []
lower (PseudoInstr op) = case op of
    P_NOP -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (ImmVal 0))
    P_MV rd rs  -> pure $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (ImmVal 0))
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

expandProgram :: [ArchInstr 'Parsed] -> [SomeInstruction Operand]
expandProgram = concatMap (NE.toList . lower) 

resolve :: ParsedProgram -> Either String Program 
resolve l = do
    symbolTable <- buildSymTable l 
    let instructions = [i | (_, Just i) <- l] -- Keep only the instructions
    let realInstructions = expandProgram instructions
    evalStateT (mapM (resolveInstruction symbolTable) realInstructions) 0 

buildSymTable :: ParsedProgram -> Either String SymbolTable 
buildSymTable l = snd <$> foldM step (0, M.empty) l
    where
        step (pc, table) (ml, mi) = do
            newTable <- case ml of
                Nothing -> Right table
                Just n  -> if M.member n table
                           then Left $ "Duplicate label: " ++ n
                           else Right $ M.insert n pc table

            let size = case mi of
                    Nothing -> 0
                    Just i  -> sum (map instrSize (NE.toList $ lower i)) 
            let !nextPC = pc + size
            return (nextPC, newTable)

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
-- Compensation for the fact that this ADDI is 4 bytes ahead of the AUIPC 
-- that started the address calculation.
--
-- Ideally we make the linker more complex later on to link instructions together
-- such that we can allow for instructions like addi a0, a0, %lo(label)
resolveRelative pc table (LabelLo l) =
    case M.lookup l table of
        Just target -> Right $ (target - pc + 4) .&. 0xFFF
        Nothing     -> Left $ "Undefined label (Lo): " ++ l

resolveAbsolute :: SymbolTable -> Operand -> Either String Int
resolveAbsolute table (Label l) = 
    case M.lookup l table of
        Just target -> Right target        -- Return actual address
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
resolveOperand pc table (SomeInstruction (SType op args)) = 
    SomeInstruction . SType op <$> traverse (resolveRelative pc table) args
resolveOperand pc table (SomeInstruction (ArithI op args)) = do
    val <- resolveRelative pc table (i_imm args) 
    validVal <- checkShiftBounds op val
    return $ SomeInstruction $ ArithI op (args { i_imm = validVal })
resolveOperand _ table (SomeInstruction instr) = 
    SomeInstruction <$> traverse (resolveAbsolute table) instr
