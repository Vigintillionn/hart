module CPU where
import Data.Word
import Types
import Data.Bits (Bits(..))
import Assembler (assembleSome)
import Data.Foldable (traverse_)
import Decoder (decodeWord)
import Control.Monad
import Data.Int
import Kernel (handleSyscall) 
import Machine
import Linker (Executable(..))
import qualified Data.IntMap.Strict as M

shiftRA :: Word32 -> Int -> Word32
shiftRA w i = fromIntegral (fromIntegral w `shiftR` i :: Int32)

lessThanSigned :: Word32 -> Word32 -> Word32
lessThanSigned a b = if (fromIntegral a :: Int32) < (fromIntegral b :: Int32) then 1 else 0

lessThanUnsigned :: Word32 -> Word32 -> Word32
lessThanUnsigned a b = if a < b then 1 else 0

shamt :: Word32 -> Int
shamt = fromIntegral . (.&. 0x1F)

sll :: Word32 -> Word32 -> Word32
sll a b = a `shiftL` shamt b

srl :: Word32 -> Word32 -> Word32
srl a b = a `shiftR` shamt b

sra :: Word32 -> Word32 -> Word32
sra a b = shiftRA a (shamt b)

incr :: Word32 -> Int -> Word32
incr w o = fromIntegral $ fromIntegral w + o

fetch :: MonadCPU m => m Word32
fetch = getPC >>= loadWord 

loadProgram :: MonadCPU m => Executable -> m ()
loadProgram (Executable instr dataMem) = do
    setPC entryPoint

    let assembled = zip [entryPoint, entryPoint + 4 ..] $ map assembleSome instr
    traverse_ (uncurry storeWord) assembled 

    traverse_ (\(addr, val) -> storeByte (fromIntegral addr) (fromIntegral val)) (M.toList dataMem)

runBinaryOp :: MonadCPU m => (Word32 -> Word32 -> Word32) -> RTypeArgs -> m ()
runBinaryOp op args = do
    l <- getReg $ r_rs1 args 
    r <- getReg $ r_rs2 args 
    setReg (r_rd args) (l `op` r)

executeRType :: MonadCPU m => Instruction 'R Int -> m PCUpdate 
executeRType (RType op args) = do
    case op of
        ADD -> runBinaryOp (+) args
        SUB -> runBinaryOp (-) args
        XOR -> runBinaryOp xor args
        OR  -> runBinaryOp (.|.) args
        AND -> runBinaryOp (.&.) args
        SLL  -> runBinaryOp sll args
        SRL  -> runBinaryOp srl args
        SRA  -> runBinaryOp sra args
        SLT  -> runBinaryOp lessThanSigned args
        SLTU -> runBinaryOp lessThanUnsigned args
    return Advance

runImmediateOp :: MonadCPU m => (Word32 -> Word32 -> Word32) -> ITypeArgs Int -> m ()
runImmediateOp op args = do
    r <- getReg $ i_rs1 args
    let imm = fromIntegral $ i_imm args
    setReg (i_rd args) (r `op` imm) 

runLoadOp :: MonadCPU m => ILoadOp -> ITypeArgs Int -> m ()
runLoadOp op args = do
    base <- getReg (i_rs1 args)
    let off = fromIntegral (i_imm args) :: Word32
    let addr = base + off

    val <- case op of
        LB -> signExt8  <$> loadByte addr
        LH -> signExt16 <$> loadHalf addr
        LW -> loadWord addr
        LBU -> zeroExt8  <$> loadByte addr
        LHU -> zeroExt16 <$> loadHalf addr

    setReg (i_rd args) val

executeIType :: MonadCPU m => Instruction 'I Int -> m PCUpdate 
executeIType (ArithI op args) = do 
    case op of
        ADDI -> runImmediateOp (+) args
        XORI -> runImmediateOp xor args
        ORI  -> runImmediateOp (.|.) args
        ANDI -> runImmediateOp (.&.) args
        SLLI -> runImmediateOp sll args
        SRLI -> runImmediateOp srl args
        SRAI -> runImmediateOp sra args
        SLTI -> runImmediateOp lessThanSigned args
        SLTIU -> runImmediateOp lessThanUnsigned args
    return Advance
executeIType (LoadI op args) = runLoadOp op args >> return Advance
executeIType (JumpI JALR args) = do
    currentPC <- getPC
    base      <- getReg (i_rs1 args)
    let imm   = fromIntegral (i_imm args) :: Word32

    setReg (i_rd args) (currentPC + 4)
    let target = (base + imm) .&. complement 1
    return $ Jump target

executeBType :: MonadCPU m => Instruction 'B Int -> m PCUpdate 
executeBType (BType op args) = do
    l <- getReg (b_rs1 args)
    r <- getReg (b_rs2 args)

    let sl = fromIntegral l :: Int32
    let sr = fromIntegral r :: Int32

    let shouldBranch = case op of
            BEQ  -> l == r
            BNE  -> l /= r
            BLT  -> sl <  sr 
            BGE  -> sl >= sr 
            BLTU -> l < r
            BGEU -> l >= r

    if shouldBranch
        then do 
            currentPC <- getPC
            let off = fromIntegral $ b_imm args
            let target = currentPC + off
            return (Jump target)
        else return Advance

executeSType :: MonadCPU m => Instruction 'S Int -> m PCUpdate
executeSType (SType op args) = do
    val <- getReg $ s_rs2 args 
    base <- getReg $ s_rs1 args
    let off = fromIntegral $ s_imm args
    let addr = base + off

    case op of
        SW -> storeWord addr val
        SH -> storeHalf addr val
        SB -> storeByte addr val
    return Advance

executeUType :: MonadCPU m => Instruction 'U Int -> m PCUpdate
executeUType (UType op args) = do
    let imm = fromIntegral $ u_imm args `shiftL` 12 :: Word32

    val <- case op of
        LUI   -> return imm
        AUIPC -> do
            currentPC <- getPC
            return $ currentPC + imm
    
    setReg (u_rd args) val

    return Advance

executeJType :: MonadCPU m => Instruction 'J Int -> m PCUpdate
executeJType (JType JAL args) = do
    currentPC <- getPC
    let off   = fromIntegral (j_imm args) :: Word32
    setReg (j_rd args) (currentPC + 4)
    return (Jump $ currentPC + off)

executeSystem :: MonadCPU m => Instruction 'Sys Int -> m PCUpdate
executeSystem (System op args) = do
    let csrAddr = c_csr args
    oldVal <- getCSR csrAddr
    rs1Val <- getReg (c_rs1 args)

    let newVal = case op of
            CSRRW -> rs1Val              
            CSRRS -> oldVal .|. rs1Val  
            CSRRC -> oldVal .&. complement rs1Val 
    setCSR csrAddr newVal        
    setReg (c_rd args) oldVal   

    return Advance
executeSystem (SystemI op args) = do
    let csrAddr = ci_csr args
    oldVal <- getCSR csrAddr
    
    let uimm = fromIntegral (ci_uimm args) :: Word32
    let newVal = case op of
            CSRRWI -> uimm
            CSRRSI -> oldVal .|. uimm
            CSRRCI -> oldVal .&. complement uimm
    setCSR csrAddr newVal
    setReg (ci_rd args) oldVal

    return Advance
executeSystem (Trap ECALL) = do
    currentPC <- getPC
    _ <- takeTrap trapECallM currentPC

    update <- Kernel.handleSyscall

    case update of
        Advance -> do
            return $ Jump (currentPC + 4)
        _ -> return update
executeSystem (Trap EBREAK) = do
        currentPC <- getPC
        _ <- takeTrap trapBreakpointM currentPC
        consolePrintLn "--- BREAKPOINT ---"
        return Breakpoint 

execute :: MonadCPU m => SomeInstruction Int -> m PCUpdate 
execute (SomeInstruction inst@(RType  _ _)) = executeRType inst 
execute (SomeInstruction inst@(ArithI _ _)) = executeIType inst 
execute (SomeInstruction inst@(LoadI  _ _)) = executeIType inst 
execute (SomeInstruction inst@(JumpI  _ _)) = executeIType inst
execute (SomeInstruction inst@(BType  _ _)) = executeBType inst
execute (SomeInstruction inst@(SType  _ _)) = executeSType inst
execute (SomeInstruction inst@(UType  _ _)) = executeUType inst
execute (SomeInstruction inst@(JType  _ _)) = executeJType inst
execute (SomeInstruction inst@(System _ _))   = executeSystem inst
execute (SomeInstruction inst@(SystemI _ _)) = executeSystem inst
execute (SomeInstruction inst@(Trap _))       = executeSystem inst

-- One clock cycle
step :: MonadCPU m => m Bool  
step = do
    curStatus <- getStatus
    if curStatus /= Running
    then return False
    else do
        w <- fetch
        if w == 0 then do
            consolePrintLn ">> End of instructions (Implicit Halt)"
            setStatus Halted 
            return False
        else do 
            incCycles 
            case decodeWord w of
                Left err -> do
                    consolePrintLn $ "Decode Error: " ++ err
                    setStatus Halted 
                    return False
                Right instr -> do
                    update <- execute instr
                    case update of
                        Advance    -> incPC  >> return True
                        Jump t     -> setPC t >> return True
                        Terminate  -> do
                            setStatus Halted 
                            return False 
                        Breakpoint -> do
                            setStatus Paused 
                            return False
    
run :: MonadCPU m => m ()
run = do
   running <- step
   when running run  

runProgram :: MonadCPU m => Executable -> m ()
runProgram p = do
    loadProgram p
    run


