module Machine (Register
               , mkRegister
               , unReg
               , PCUpdate(..)
               , RunStatus(..)
               , CPU(..)
               , Emulator(..)
               , MonadCPU(..)
               , emptyCPU
               , x0
               , x1
               , x6
               , a0
               , a1
               , a2
               , a7
               , trapECallM
               , trapBreakpointM
               , entryPoint
               , stackTop
               , extractByte
               , incPC
               , storeHalf
               , storeWord
               , loadHalf
               , loadWord
               , signExt8
               , signExt16
               , zeroExt8
               , zeroExt16
               , takeTrap
               )
where

import Data.Word (Word32, Word8, Word16)
import qualified Data.Vector as V
import qualified Data.IntMap.Strict as M
import Control.Monad.State 
import Data.Vector ((!), (//))
import Data.Int (Int8, Int16)
import Data.Bits (Bits(..))
import System.IO (hFlush, stdout) 

class Monad m => MonadCPU m where
    getReg     :: Register -> m Word32
    setReg     :: Register -> Word32 -> m ()
    getCSR     :: Int -> m Word32
    setCSR     :: Int -> Word32 -> m ()

    loadByte   :: Word32 -> m Word8
    storeByte  :: Word32 -> Word32 -> m ()

    getPC      :: m Word32
    setPC      :: Word32 -> m ()
    getCycles  :: m Int
    incCycles  :: m ()
    getStatus  :: m RunStatus
    setStatus  :: RunStatus -> m ()

    consolePrintLn :: String -> m ()
    consolePrint   :: String -> m ()
    consoleRead    :: m String 
    terminate      :: m ()

newtype Register = Reg { unReg :: Int } deriving (Show, Eq, Ord)

data PCUpdate = Advance | Jump Word32 | Terminate | Breakpoint

data RunStatus = Running | Halted | Paused
    deriving (Show, Eq)

data CPU = CPU 
    { pc     :: Word32 
    , regs   :: V.Vector Word32 
    , csrs   :: M.IntMap Word32
    , mem    :: M.IntMap Word8 
    , cycles :: Int
    , status :: RunStatus
    }

newtype Emulator a = Emulator
  { runEmulator :: StateT CPU IO a
  }
  deriving (Functor, Applicative, Monad, MonadIO, MonadState CPU)

instance MonadCPU Emulator where
    getReg r  
        | unReg r == 0 = return 0
        | otherwise = do
            file <- gets regs
            return (file ! unReg r)
    setReg r v
        | unReg r == 0 = return ()
        | otherwise =  modify $ \cpu -> cpu { regs = regs cpu // [(unReg r, v)]  } 
    getCSR addr = gets $ M.findWithDefault 0 addr . csrs
    setCSR addr val = modify $ \cpu -> cpu { csrs = M.insert addr val (csrs cpu) }

    loadByte a = gets $ M.findWithDefault 0 (fromIntegral a) . mem
    storeByte a w = modify $ \cpu ->
        cpu { mem = M.insert (fromIntegral a) (fromIntegral $ w .&. 0xFF) (mem cpu) }

    getPC = gets pc 
    setPC t = modify $ \cpu -> cpu { pc = t }
    getCycles = gets cycles
    incCycles = modify $ \cpu -> cpu { cycles = cycles cpu + 1 }
    getStatus = gets status
    setStatus s = modify $ \cpu -> cpu { status = s }

    consolePrintLn m = liftIO $ putStrLn m
    consolePrint m = liftIO $ do
        putStr m
        hFlush stdout
    consoleRead = liftIO getLine
    terminate = modify $ \cpu -> cpu { status = Halted }

x0, x1, x6, a0, a1, a2, a7 :: Register
x0 = Reg 0
x1 = Reg 1
x6 = Reg 6
a0 = Reg 10
a1 = Reg 11
a2 = Reg 12
a7 = Reg 17

trapECallM, trapBreakpointM :: Word32
trapECallM      = 11
trapBreakpointM = 3

mkRegister :: Int -> Maybe Register
mkRegister n
    | n >= 0 && n < 32 = Just (Reg n)
    | otherwise        = Nothing

entryPoint :: Word32
entryPoint = 0x0

stackTop :: Word32
stackTop = 0x100000 -- 1MB

emptyCPU :: CPU
emptyCPU = CPU 
    { pc     = entryPoint 
    , regs   = V.replicate 32 0 // [(2, stackTop)]
    , csrs   = M.empty
    , mem    = M.empty
    , cycles = 0 
    , status = Running
    }

incPC :: MonadCPU m => m ()
incPC = do
    current <- getPC
    setPC (current + 4)

extractByte :: Word32 -> Int -> Word8
extractByte w n = fromIntegral $ (w `shiftR` (n * 8)) .&. 0xFF 

storeHalf :: MonadCPU m => Word32 -> Word32 -> m ()
storeHalf a w = do
    storeByte a       (w .&. 0xFF)   -- LSB
    storeByte (a + 1) (w `shiftR` 8) -- Next byte

storeWord :: MonadCPU m => Word32 -> Word32 -> m ()
storeWord a w = do
    storeHalf a       (w .&. 0xFFFF)  -- Lower half
    storeHalf (a + 2) (w `shiftR` 16) -- Upper half

loadHalf :: MonadCPU m => Word32 -> m Word16
loadHalf a = do
    b0 <- loadByte a
    b1 <- loadByte $ a + 1 
    return $ fromIntegral b0 .|. (fromIntegral b1 `shiftL` 8)

loadWord :: MonadCPU m => Word32 -> m Word32
loadWord a = do
    lower <- loadHalf a
    upper <- loadHalf (a + 2)
    return $ fromIntegral lower .|. (fromIntegral upper `shiftL` 16)

signExt8 :: Word8 -> Word32
signExt8 w = fromIntegral (fromIntegral w :: Int8)

signExt16 :: Word16 -> Word32
signExt16 w = fromIntegral (fromIntegral w :: Int16)

zeroExt8 :: Word8 -> Word32
zeroExt8 = fromIntegral 

zeroExt16 :: Word16 -> Word32
zeroExt16 = fromIntegral

takeTrap :: MonadCPU m => Word32 -> Word32 -> m PCUpdate
takeTrap causeCode currentPC = do
    setCSR 0x341 currentPC -- 0x341 is MEPC
    setCSR 0x342 causeCode -- 0x342 is MCAUSE
    setCSR 0x343 0         -- 0x343 is MTVAL
    handlerAddr <- getCSR 0x305 
    
    let target = if handlerAddr == 0 then 0x80000000 else handlerAddr
    
    return $ Jump target
