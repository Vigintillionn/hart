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
import Data.Int

data PCUpdate = Advance | Jump Word32

data CPU = CPU 
    { pc    :: Word32 
    , regs  :: V.Vector Word32 
    , mem   :: M.IntMap Word8 
    }

entryPoint :: Word32
entryPoint = 0x0

stackTop :: Word32
stackTop = 0x100000 -- 1MB

emptyCPU :: CPU
emptyCPU = CPU 
    { pc    = entryPoint 
    , regs  = V.replicate 32 0 // [(2, stackTop)]
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

storeByte :: Word32 -> Word32 -> Emulator ()
storeByte a w = modify $ \cpu ->
    cpu { mem = M.insert (fromIntegral a) (fromIntegral $ w .&. 0xFF) (mem cpu) }

storeHalf :: Word32 -> Word32 -> Emulator ()
storeHalf a w = do
    storeByte a       (w .&. 0xFF)   -- LSB
    storeByte (a + 1) (w `shiftR` 8) -- Next byte

storeWord :: Word32 -> Word32 -> Emulator ()
storeWord a w = do
    storeHalf a       (w .&. 0xFFFF)  -- Lower half
    storeHalf (a + 2) (w `shiftR` 16) -- Upper half

readByte :: Word32 -> Emulator Word8 
readByte a = gets $ M.findWithDefault 0 (fromIntegral a) . mem

loadHalf :: Word32 -> Emulator Word16
loadHalf a = do
    b0 <- readByte a
    b1 <- readByte $ a + 1 
    return $ fromIntegral b0 .|. (fromIntegral b1 `shiftL` 8)

loadWord :: Word32 -> Emulator Word32
loadWord a = do
    lower <- loadHalf a
    upper <- loadHalf (a + 2)
    return $ fromIntegral lower .|. (fromIntegral upper `shiftL` 16)

signExt8 :: Word8 -> Word32
signExt8 w = fromIntegral (fromIntegral w :: Int8)

signExt16 :: Word16 -> Word32
signExt16 w = fromIntegral (fromIntegral w :: Int16)

incr :: Word32 -> Int -> Word32
incr w o = fromIntegral $ fromIntegral w + o

fetch :: Emulator Word32
fetch = gets pc >>= loadWord 

loadProgram :: Program -> Emulator ()
loadProgram instr = do
    modify $ \cpu -> cpu { pc = entryPoint }
    let assembled = zip [entryPoint, entryPoint + 4 ..] $ map assembleSome instr
    traverse_ (uncurry storeWord) assembled 

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

runLoadOp :: ILoadOp -> ITypeArgs Int -> Emulator ()
runLoadOp op args = do
    base <- getReg (i_rs1 args)
    let off = fromIntegral (i_imm args) :: Word32
    let addr = base + off

    val <- case op of
        LB -> signExt8 <$> readByte addr
        LH -> signExt16 <$> loadHalf addr
        LW -> loadWord addr

    setReg (i_rd args) val

executeIType :: Instruction 'I Int -> Emulator PCUpdate 
executeIType (ArithI op args) = do 
    case op of
        ADDI -> runImmediateOp (+) args
        XORI -> runImmediateOp xor args
        ORI  -> runImmediateOp (.|.) args
        ANDI -> runImmediateOp (.&.) args
    return Advance
executeIType (LoadI op args) = runLoadOp op args >> return Advance

executeBType :: Instruction 'B Int -> Emulator PCUpdate 
executeBType (BType op args) = do
    l <- getReg (b_rs1 args)
    r <- getReg (b_rs2 args)

    let shouldBranch = case op of
            BEQ -> l == r
            BNE -> l /= r
            BLT -> l <  r
            BGE -> l >= r

    if shouldBranch
        then do 
            currentPC <- gets pc
            let off = fromIntegral $ b_imm args
            let target = currentPC + off
            return (Jump target)
        else return Advance

executeSType :: Instruction 'S Int -> Emulator PCUpdate
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

execute :: SomeInstruction Int -> Emulator PCUpdate 
execute (SomeInstruction inst@(RType  _ _)) = executeRType inst 
execute (SomeInstruction inst@(ArithI _ _)) = executeIType inst 
execute (SomeInstruction inst@(LoadI  _ _)) = executeIType inst 
execute (SomeInstruction inst@(BType  _ _)) = executeBType inst
execute (SomeInstruction inst@(SType  _ _)) = executeSType inst


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
