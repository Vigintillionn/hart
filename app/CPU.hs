module CPU where
import Data.Word
import qualified Data.Vector as V
import qualified Data.IntMap.Strict as M
import Types
import Control.Monad.State 
import Data.Vector ((!), (//))
import Data.Bits (Bits(..))
import Assembler (assembleSome)
import Data.Foldable (traverse_)
import Decoder (decodeWord)
import Control.Monad

data PCUpdate = Advance | Jump Word32

data CPU = CPU 
    { pc    :: Word32 
    , regs  :: V.Vector Word32 
    , mem   :: M.IntMap Word8 
    }

entryPoint :: Word32
entryPoint = 0x0

emptyCPU :: CPU
emptyCPU = CPU 
    { pc    = entryPoint 
    , regs  = V.replicate 32 0
    , mem   = M.empty
    }

type Emulator a = State CPU a 

getReg :: Register -> Emulator Word32 
getReg r  
    | unReg r == 0 = return 0
    | otherwise = do
        file <- gets regs
        return (file ! unReg r)

setReg :: Register -> Word32 -> Emulator ()
setReg r v
    | unReg r == 0 = return ()
    | otherwise = do
        modify $ \cpu ->
            cpu { regs = regs cpu // [(unReg r, v)]  } 

extractByte :: Word32 -> Int -> Word8
extractByte w n = fromIntegral $ (w `shiftR` (n * 8)) .&. 0xFF 

store :: Word32 -> Word32 -> Emulator ()
store a w = modify $ \cpu ->
    let addr = fromIntegral a
        m0 = M.insert addr       (extractByte w 0) (mem cpu)
        m1 = M.insert (addr + 1) (extractByte w 1) m0
        m2 = M.insert (addr + 2) (extractByte w 2) m1
        m3 = M.insert (addr + 3) (extractByte w 3) m2
    in cpu { mem = m3 } 
    
readByte :: Word32 -> Emulator Word8 
readByte a = gets $ M.findWithDefault 0 (fromIntegral a) . mem

incr :: Word32 -> Int -> Word32
incr w o = fromIntegral $ fromIntegral w + o

fetch :: Emulator Word32
fetch = do
    p   <- gets pc
    b0  <- readByte p          -- LSB
    b1  <- readByte (p + 1)
    b2  <- readByte (p + 2)
    b3  <- readByte (p + 3)    -- MSB
    return $
        fromIntegral b0 .|.
        (fromIntegral b1 `shiftL` 8) .|.
        (fromIntegral b2 `shiftL` 16) .|.
        (fromIntegral b3 `shiftL` 24)

loadProgram :: Program -> Emulator ()
loadProgram instr = do
    modify $ \cpu -> cpu { pc = entryPoint }
    let assembled = zip [entryPoint, entryPoint + 4 ..] $ map assembleSome instr
    traverse_ (uncurry store) assembled 

runBinaryOp :: (Word32 -> Word32 -> Word32) -> RTypeArgs -> Emulator ()
runBinaryOp op args = do
    l <- getReg $ r_rs1 args 
    r <- getReg $ r_rs2 args 
    setReg (r_rd args) (l `op` r)

executeRType :: Instruction 'R Int -> Emulator PCUpdate 
executeRType (RType op args) = do
    case op of
        ADD -> runBinaryOp (+) args
        SUB -> runBinaryOp (-) args
        XOR -> runBinaryOp xor args
        OR  -> runBinaryOp (.|.) args
        AND -> runBinaryOp (.&.) args
    return Advance

runImmediateOp :: (Word32 -> Word32 -> Word32) -> ITypeArgs Int -> Emulator ()
runImmediateOp op args = do
    r <- getReg $ i_rs1 args
    let imm = fromIntegral $ i_imm args
    setReg (i_rd args) (r `op` imm) 

executeIType :: Instruction 'I Int -> Emulator PCUpdate 
executeIType (IType op args) = do 
    case op of
        ADDI -> runImmediateOp (+) args
        XORI -> runImmediateOp xor args
        ORI  -> runImmediateOp (.|.) args
        ANDI -> runImmediateOp (.&.) args
    return Advance

executeBType :: Instruction 'B Int -> Emulator PCUpdate 
executeBType (BType op args) = do
    l <- getReg (b_rs1 args)
    r <- getReg (b_rs2 args)

    let shouldBranch = case op of
            BEQ -> l == r
            BNE -> l /= r

    if shouldBranch
        then do 
            currentPC <- gets pc
            let off = fromIntegral $ b_imm args
            let target = currentPC + off
            return (Jump target)
        else return Advance

execute :: SomeInstruction Int -> Emulator PCUpdate 
execute (SomeInstruction inst@(RType _ _)) = executeRType inst 
execute (SomeInstruction inst@(IType _ _)) = executeIType inst 
execute (SomeInstruction inst@(BType _ _)) = executeBType inst


setPC :: Word32 -> Emulator ()
setPC t = modify $ \cpu -> cpu { pc = t }

incrPC :: Emulator ()
incrPC = modify $ \cpu -> cpu { pc = pc cpu + 4 }

-- One clock cycle
step :: Emulator ()
step = 
    fetch >>= either (const $ pure ()) execInstr . decodeWord
    where
        execInstr i =
            execute i >>= \case
                Advance -> incrPC
                Jump t  -> setPC t

run :: Emulator ()
run = do
    step
    w <- fetch
    unless (w == 0x0) run

runProgram :: Program -> Emulator ()
runProgram p = do
    loadProgram p
    run
