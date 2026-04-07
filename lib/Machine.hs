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
               , sp
               , x6
               , a0
               , a1
               , a2
               , a7
               , trapECallM
               , trapBreakpointM
               , trapLoadMisaligned
               , trapStoreMisaligned
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
import System.IO (hFlush, stdout, Handle, IOMode (..), openFile, hClose)
import Numeric (showHex)
import Control.Exception (SomeException, try)
import qualified Data.ByteString as BS

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

    getHeapTop  :: m Word32
    setHeapTop  :: Word32 -> m ()

    openHostFile    :: String -> Int -> m Int
    closeHostFile   :: Int -> m Int
    readHostFile    :: Int -> Int -> m [Word8]
    writeHostFile   :: Int -> [Word8] -> m Int

newtype Register = Reg { unReg :: Int } deriving (Show, Eq, Ord)

data PCUpdate = Advance | Jump Word32 | Terminate | Breakpoint

data RunStatus = Running | Halted | Paused
    deriving (Show, Eq)

data CPU = CPU
    { pc        :: Word32
    , regs      :: V.Vector Word32
    , csrs      :: M.IntMap Word32
    , mem       :: M.IntMap Word8
    , cycles    :: Int
    , status    :: RunStatus
    , heapTop   :: Word32
    , fileMap   :: M.IntMap Handle
    , nextFD    :: Int
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

    getHeapTop = gets heapTop
    setHeapTop addr = modify $ \cpu -> cpu { heapTop = addr }

    openHostFile path flags = do
        let mode
              | flags == 0 = ReadMode
              | flags == 1 = WriteMode
              | otherwise = ReadWriteMode

        res <- liftIO (try (openFile path mode) :: IO (Either SomeException Handle))

        case res of
            Left _ -> return (-1)
            Right h -> do
                fd <- gets nextFD
                modify $ \cpu -> cpu { fileMap = M.insert fd h (fileMap cpu), nextFD = fd + 1 }
                return fd
    closeHostFile fd = do
        mmap <- gets fileMap
        case M.lookup fd mmap of
            Nothing -> return (-1)
            Just h -> do
                _ <- liftIO (try (hClose h) :: IO (Either SomeException ()))
                modify $ \cpu -> cpu { fileMap = M.delete fd (fileMap cpu) }
                return 0
    readHostFile fd len = do
        mmap <- gets fileMap
        case M.lookup fd mmap of
            Nothing -> return []
            Just h -> do
                bytes <- liftIO (try (BS.hGet h len) :: IO (Either SomeException BS.ByteString))
                case bytes of
                    Left _  -> return []
                    Right b -> return (BS.unpack b)

    writeHostFile fd bytes = do
        mmap <- gets fileMap
        case M.lookup fd mmap of
            Nothing -> return (-1)
            Just h -> do
                res <- liftIO (try (BS.hPut h (BS.pack bytes)) :: IO (Either SomeException ()))
                case res of
                    Left _  -> return (-1)
                    Right _ -> return (length bytes)

x0, x1, sp, x6, a0, a1, a2, a7 :: Register
x0 = Reg 0
x1 = Reg 1
sp = Reg 2
x6 = Reg 6
a0 = Reg 10
a1 = Reg 11
a2 = Reg 12
a7 = Reg 17

trapECallM, trapBreakpointM, trapStoreMisaligned, trapLoadMisaligned :: Word32
trapECallM      = 11
trapBreakpointM = 3
trapLoadMisaligned  = 4
trapStoreMisaligned = 6

mkRegister :: Int -> Maybe Register
mkRegister n
    | n >= 0 && n < 32 = Just (Reg n)
    | otherwise        = Nothing

entryPoint :: Word32
entryPoint = 0x0

stackTop :: Word32
stackTop = 0x7FFFFFFF   -- ~ 2GB

emptyCPU :: CPU
emptyCPU = CPU
    { pc        = entryPoint
    , regs      = V.replicate 32 0 // [(2, stackTop)]
    , csrs      = M.empty
    , mem       = M.empty
    , cycles    = 0
    , status    = Running
    , heapTop   = 0x20000000
    , fileMap   = M.empty
    , nextFD    = 3
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

takeTrap :: MonadCPU m => Word32 -> Word32 -> Word32 -> m PCUpdate
takeTrap causeCode currentPC tval = do
    setCSR 0x341 currentPC -- 0x341 is MEPC
    setCSR 0x342 causeCode -- 0x342 is MCAUSE
    setCSR 0x343 tval      -- 0x343 is MTVAL
    handlerAddr <- getCSR 0x305

    let target = if handlerAddr == 0 then 0x80000000 else handlerAddr

    case causeCode of
            4 -> consolePrintLn $ "\n[!] HARDWARE EXCEPTION: Load Address Misaligned! (Bad address: 0x" ++ showHex tval "" ++ ")"
            6 -> consolePrintLn $ "\n[!] HARDWARE EXCEPTION: Store Address Misaligned! (Bad address: 0x" ++ showHex tval "" ++ ")"
            _ -> return ()

    return $ Jump target
