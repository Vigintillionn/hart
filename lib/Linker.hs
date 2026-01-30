module Linker where
import Types 
import qualified Data.Map.Strict as M
import Control.Monad (foldM)
import Control.Monad.State
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

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
resolveImm e (Label _)  = Left e

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

resolveAbsolute :: SymbolTable -> Operand -> Either String Int
resolveAbsolute table (Label l) = 
    case M.lookup l table of
        Just target -> Right target        -- Return actual address
        Nothing     -> Left $ "Undefined label: " ++ l
resolveAbsolute _ (ImmVal v) = Right v

resolveOperand :: Int -> SymbolTable -> SomeInstruction Operand -> Either String (SomeInstruction Int)
resolveOperand pc table (SomeInstruction (JType op args)) 
    = SomeInstruction . JType op <$> traverse (resolveRelative pc table) args
resolveOperand pc table (SomeInstruction (BType op args))
    = SomeInstruction . BType op <$> traverse (resolveRelative pc table) args
resolveOperand _ table (SomeInstruction instr) = 
    SomeInstruction <$> traverse (resolveAbsolute table) instr
