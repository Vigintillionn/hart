module Linker where
import Types 
import qualified Data.Map.Strict as M
import Control.Monad (foldM)
import Control.Monad.State
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

type SymbolTable = M.Map String Int

lower :: ArchInstr 'Parsed -> NonEmpty (ArchInstr 'Lowered)
lower (RealInstr i) = RealInstr i :| []
lower (PseudoInstr op) = case op of
    P_NOP -> pure $ RealInstr $ SomeInstruction $ ArithI ADDI (ITypeArgs x0 x0 (ImmVal 0))
    P_MV rd rs -> pure $ RealInstr $ SomeInstruction $ ArithI ADDI (ITypeArgs rd rs (ImmVal 0))

expandProgram :: [ArchInstr 'Parsed] -> [ArchInstr 'Lowered]
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
                    Just i  -> length (lower i) * 4
            let nextPC = pc + size
            return (nextPC, newTable)

resolveImm :: String -> Operand -> Either String Int
resolveImm _ (ImmVal v) = Right v
resolveImm e (Label _)  = Left e

resolveInstruction :: SymbolTable -> ArchInstr 'Lowered -> StateT Int (Either String) (ArchInstr 'Resolved)
resolveInstruction table (RealInstr instr) = do
    pc <- get
    resolved <- lift $ resolveOperand pc table instr
    modify (+4)
    return $ RealInstr resolved

resolveOperand :: Int -> SymbolTable -> SomeInstruction Operand -> Either String (SomeInstruction Int)
resolveOperand pc table (SomeInstruction (BType op args)) = do
    off <- case b_imm args of
        ImmVal v -> Right v
        Label l     -> case M.lookup l table of
            Just target -> Right (target - pc)
            Nothing     -> Left $ "Undefined label: " ++ l
    return $ SomeInstruction (BType op (args { b_imm = off }))
resolveOperand _ _ (SomeInstruction (LoadI op args)) = do
    val <- resolveImm "Label in load immediate" (i_imm args)
    return $ SomeInstruction (LoadI op (args { i_imm = val }))
resolveOperand _ _ (SomeInstruction (ArithI op args)) = do
    val <- resolveImm "Label in arithmatic immediate" (i_imm args)
    return $ SomeInstruction (ArithI op (args { i_imm = val }))
resolveOperand _ _ (SomeInstruction (SType op args)) = do
    val <- resolveImm "Label in store instruction" (s_imm args)
    return $ SomeInstruction (SType op (args { s_imm = val }))
resolveOperand _ _ (SomeInstruction (RType op args)) = Right $ SomeInstruction $ RType op args
