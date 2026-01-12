module Linker where
import Types 
import qualified Data.Map.Strict as M
import Control.Monad (foldM)

resolve :: [SourceLine] -> Either String [SomeInstruction]
resolve l = do
    symbolTable <- buildSymTable l 
    resolveInstructions l 0 symbolTable

buildSymTable :: [SourceLine] -> Either String (M.Map String Int)
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

resolveInstructions :: [SourceLine] -> Int -> M.Map String Int -> Either String [SomeInstruction]
resolveInstructions [] _ _  = Right []
resolveInstructions ((_, Nothing) : xs) pc table = resolveInstructions xs pc table
resolveInstructions ((_, Just i) : xs) pc table = do
    resolved <- resolveOperand pc table i
    rest <- resolveInstructions xs (pc + 4) table
    return (resolved : rest)

resolveOperand :: Int -> M.Map String Int -> SomeInstruction -> Either String SomeInstruction
resolveOperand pc table (SomeInstruction (BType op args)) = do
    off <- case b_imm args of
        Immediate v -> Right v
        Label l     -> case M.lookup l table of
            Just target -> Right (target - pc)
            Nothing     -> Left $ "Undefined label: " ++ l
    return $ SomeInstruction (BType op (args { b_imm = Immediate off }))
resolveOperand _ _ (SomeInstruction (IType op args)) = do
    case i_imm args of
        Immediate _ -> Right $ SomeInstruction (IType op args)
        Label _     -> Left "Label in immediate instruction."
resolveOperand _ _ instr = Right instr
