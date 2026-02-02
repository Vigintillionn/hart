module Machine (Register
               , mkRegister
               , unReg
               , getReg
               , setReg
               , getCSR
               , setCSR
               , PCUpdate(..)
               , RunStatus(..)
               , CPU(..)
               , Emulator
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
               , storeByte
               , storeHalf
               , storeWord
               , loadByte
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

type Emulator a = StateT CPU IO a 

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

getCSR :: Int -> Emulator Word32
getCSR addr = gets $ M.findWithDefault 0 addr . csrs

setCSR :: Int -> Word32 -> Emulator ()
setCSR addr val = modify $ \cpu -> 
    cpu { csrs = M.insert addr val (csrs cpu) }

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

loadByte :: Word32 -> Emulator Word8 
loadByte a = gets $ M.findWithDefault 0 (fromIntegral a) . mem

loadHalf :: Word32 -> Emulator Word16
loadHalf a = do
    b0 <- loadByte a
    b1 <- loadByte $ a + 1 
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

zeroExt8 :: Word8 -> Word32
zeroExt8 = fromIntegral 

zeroExt16 :: Word16 -> Word32
zeroExt16 = fromIntegral

takeTrap :: Word32 -> Word32 -> Emulator PCUpdate
takeTrap causeCode currentPC = do
    setCSR 0x341 currentPC -- 0x341 is MEPC
    setCSR 0x342 causeCode -- 0x342 is MCAUSE
    setCSR 0x343 0         -- 0x343 is MTVAL
    handlerAddr <- getCSR 0x305 
    
    let target = if handlerAddr == 0 then 0x80000000 else handlerAddr
    
    return $ Jump target
