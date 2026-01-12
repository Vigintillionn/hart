module Linker where
import Types 
import qualified Data.Map.Strict as M
import Control.Monad (foldM)

resolve :: ParsedProgram -> Either String Program 
resolve l = do
    symbolTable <- buildSymTable l 
    resolveInstructions l 0 symbolTable

buildSymTable :: ParsedProgram -> Either String (M.Map String Int)
buildSymTable l = snd <$> foldM step (0, M.empty) l
    where
        step (pc, table) (ml, mi) = do
            newTable <- case ml of
                Nothing -> Right table
                Just n  -> if M.member n table
                           then Left $ "Duplicate label: " ++ n
                           else Right $ M.insert n pc table

            let nextPC = case mi of
                    Nothing -> pc
                    Just _  -> pc + 4

            return (nextPC, newTable)

resolveInstructions :: ParsedProgram -> Int -> M.Map String Int -> Either String Program 
resolveInstructions [] _ _  = Right []
resolveInstructions ((_, Nothing) : xs) pc table = resolveInstructions xs pc table
resolveInstructions ((_, Just i) : xs) pc table = do
    resolved <- resolveOperand pc table i
    rest <- resolveInstructions xs (pc + 4) table
    return (resolved : rest)

resolveOperand :: Int -> M.Map String Int -> SomeInstruction Operand -> Either String (SomeInstruction Int)
resolveOperand pc table (SomeInstruction (BType op args)) = do
    off <- case b_imm args of
        ImmVal v -> Right v
        Label l     -> case M.lookup l table of
            Just target -> Right (target - pc)
            Nothing     -> Left $ "Undefined label: " ++ l
    return $ SomeInstruction (BType op (args { b_imm = off }))
resolveOperand _ _ (SomeInstruction (IType op args)) = do
    case i_imm args of
        ImmVal v -> Right $ SomeInstruction $ IType op (args { i_imm = v })
        Label _  -> Left "Label in immediate instruction."
resolveOperand _ _ (SomeInstruction (RType op args)) = Right $ SomeInstruction $ RType op args
