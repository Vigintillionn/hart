module Linker where
import Types 
import qualified Data.Map.Strict as M

resolve :: [SourceLine] -> Either String [SomeInstruction]
resolve l = do
    symbolTable <- buildSymTable l 0 M.empty
    resolveInstructions l 0 symbolTable

buildSymTable :: [SourceLine] -> Int -> M.Map String Int -> Either String (M.Map String Int)
buildSymTable [] _ table = Right table
buildSymTable ((l, i) : xs) pc table = do
    newTable <- case l of
        Just name -> if M.member name table
                     then Left $ "Duplicate label: " ++ name
                     else Right $ M.insert name pc table
        Nothing   -> Right table

    let nextPC = case i of
            Just _  -> pc + 4
            Nothing -> pc

    buildSymTable xs nextPC newTable

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
