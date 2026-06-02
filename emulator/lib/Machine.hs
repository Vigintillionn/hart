{-# LANGUAGE OverloadedStrings #-}

module Machine
  ( Register,
    mkRegister,
    unReg,
    PCUpdate (..),
    RunStatus (..),
    CPU (..),
    Output,
    emptyOutput,
    appendOutput,
    renderOutput,
    Emulator (..),
    MonadCPU (..),
    emptyCPU,
    x0,
    x1,
    sp,
    x6,
    a0,
    a1,
    a2,
    a7,
    trapECallM,
    trapBreakpointM,
    trapLoadMisaligned,
    trapStoreMisaligned,
    trapInstrMisaligned,
    trapIllegalInstr,
    clearTrapState,
    entryPoint,
    stackTop,
    extractByte,
    incPC,
    storeHalf,
    storeWord,
    loadHalf,
    loadWord,
    signExt8,
    signExt16,
    zeroExt8,
    zeroExt16,
    takeTrap,
  )
where

import Control.Exception (SomeException, try)
import Control.Monad.State.Strict
import Data.Aeson (ToJSON (..), object, (.=))
import Data.Bits (Bits (..))
import Data.ByteString qualified as BS
import Data.Int (Int16, Int8)
import Data.IntMap.Strict qualified as M
import Data.Vector.Unboxed ((//))
import Data.Vector.Unboxed qualified as V
import Data.Word (Word16, Word32, Word8)
import Error (EmulatorError (..), Notice, SystemEvent (..))
import System.IO (Handle, IOMode (..), hClose, openFile)

class (Monad m) => MonadCPU m where
  getReg :: Register -> m Word32
  setReg :: Register -> Word32 -> m ()
  getCSR :: Int -> m Word32
  setCSR :: Int -> Word32 -> m ()

  loadByte :: Word32 -> m Word8
  storeByte :: Word32 -> Word32 -> m ()

  getPC :: m Word32
  setPC :: Word32 -> m ()
  getCycles :: m Int
  incCycles :: m ()
  getStatus :: m RunStatus
  setStatus :: RunStatus -> m ()

  consolePrintLn :: String -> m ()
  consolePrint :: String -> m ()
  consoleRead :: m String
  terminate :: m ()

  logFault :: EmulatorError -> m ()
  logNotice :: Notice -> m ()

  getInputBuffer :: m (Maybe String)
  clearInputBuffer :: m ()

  getHeapTop :: m Word32
  setHeapTop :: Word32 -> m ()

  openHostFile :: String -> Int -> m Int
  closeHostFile :: Int -> m Int
  readHostFile :: Int -> Int -> m [Word8]
  writeHostFile :: Int -> [Word8] -> m Int

newtype Register = Reg {unReg :: Int} deriving (Show, Eq, Ord)

data PCUpdate = Advance | Jump Word32 | Terminate | Breakpoint | RequestInput

data RunStatus = Running | Halted | Paused | WaitingForInput
  deriving (Show, Eq)

instance ToJSON RunStatus where
  toJSON Running = "Running"
  toJSON Halted = "Halted"
  toJSON Paused = "Paused"
  toJSON WaitingForInput = "WaitingForInput"

newtype Output = Output [String]

emptyOutput :: Output
emptyOutput = Output []

appendOutput :: String -> Output -> Output
appendOutput s (Output chunks) = Output (s : chunks)

renderOutput :: Output -> String
renderOutput (Output chunks) = concat (reverse chunks)

instance ToJSON Output where
  toJSON = toJSON . renderOutput

data CPU = CPU
  { pc :: !Word32,
    regs :: !(V.Vector Word32),
    csrs :: !(M.IntMap Word32),
    mem :: !(M.IntMap Word8),
    cycles :: !Int,
    status :: !RunStatus,
    heapTop :: !Word32,
    fileMap :: !(M.IntMap Handle),
    nextFD :: !Int,
    outputBuffer :: !Output,
    systemLog :: ![SystemEvent],
    inputBuffer :: !(Maybe String)
  }

instance ToJSON CPU where
  toJSON cpu =
    object
      [ "pc" .= pc cpu,
        "regs" .= V.toList (regs cpu),
        "csrs" .= csrs cpu,
        "mem" .= mem cpu,
        "cycles" .= cycles cpu,
        "status" .= status cpu,
        "heapTop" .= heapTop cpu,
        "outputBuffer" .= outputBuffer cpu,
        "systemLog" .= reverse (systemLog cpu),
        "inputBuffer" .= inputBuffer cpu
      ]

newtype Emulator a = Emulator
  { runEmulator :: StateT CPU IO a
  }
  deriving (Functor, Applicative, Monad, MonadIO, MonadState CPU)

instance MonadCPU Emulator where
  getReg = sharedGetReg
  setReg = sharedSetReg
  getCSR = sharedGetCSR
  setCSR = sharedSetCSR
  loadByte = sharedLoadByte
  storeByte = sharedStoreByte

  -- TOOD: make others shared as well so we can have RPCEmulator easily reuse
  getPC = gets pc
  setPC t = modify' $ \cpu -> cpu {pc = t}
  getCycles = gets cycles
  incCycles = modify' $ \cpu -> cpu {cycles = cycles cpu + 1}
  getStatus = gets status
  setStatus s = modify' $ \cpu -> cpu {status = s}

  consolePrintLn m = modify' $ \cpu -> cpu {outputBuffer = appendOutput (m ++ "\n") (outputBuffer cpu)}
  consolePrint m = modify' $ \cpu -> cpu {outputBuffer = appendOutput m (outputBuffer cpu)}
  consoleRead = liftIO getLine
  terminate = modify' $ \cpu -> cpu {status = Halted}

  logFault e = modify' $ \cpu -> cpu {systemLog = SysFault e : systemLog cpu}
  logNotice n = modify' $ \cpu -> cpu {systemLog = SysNotice n : systemLog cpu}

  getInputBuffer = gets inputBuffer
  clearInputBuffer = modify' $ \cpu -> cpu {inputBuffer = Nothing}

  getHeapTop = gets heapTop
  setHeapTop addr = modify' $ \cpu -> cpu {heapTop = addr}

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
        modify' $ \cpu -> cpu {fileMap = M.insert fd h (fileMap cpu), nextFD = fd + 1}
        return fd
  closeHostFile fd = do
    mmap <- gets fileMap
    case M.lookup fd mmap of
      Nothing -> return (-1)
      Just h -> do
        _ <- liftIO (try (hClose h) :: IO (Either SomeException ()))
        modify' $ \cpu -> cpu {fileMap = M.delete fd (fileMap cpu)}
        return 0
  readHostFile fd len = do
    mmap <- gets fileMap
    case M.lookup fd mmap of
      Nothing -> return []
      Just h -> do
        bytes <- liftIO (try (BS.hGet h len) :: IO (Either SomeException BS.ByteString))
        case bytes of
          Left _ -> return []
          Right b -> return (BS.unpack b)

  writeHostFile fd bytes = do
    mmap <- gets fileMap
    case M.lookup fd mmap of
      Nothing -> return (-1)
      Just h -> do
        res <- liftIO (try (BS.hPut h (BS.pack bytes)) :: IO (Either SomeException ()))
        case res of
          Left _ -> return (-1)
          Right _ -> return (length bytes)

sharedGetReg :: (MonadState CPU m) => Register -> m Word32
sharedGetReg r
  | unReg r == 0 = return 0
  | otherwise = do
      file <- gets regs
      return (file V.! unReg r)

sharedSetReg :: (MonadState CPU m) => Register -> Word32 -> m ()
sharedSetReg r v
  | unReg r == 0 = return ()
  | otherwise = modify' $ \cpu -> cpu {regs = regs cpu V.// [(unReg r, v)]}

sharedGetCSR :: (MonadState CPU m) => Int -> m Word32
sharedGetCSR addr = gets $ M.findWithDefault 0 addr . csrs

sharedSetCSR :: (MonadState CPU m) => Int -> Word32 -> m ()
sharedSetCSR addr val = modify' $ \cpu -> cpu {csrs = M.insert addr val (csrs cpu)}

sharedLoadByte :: (MonadState CPU m) => Word32 -> m Word8
sharedLoadByte a = gets $ M.findWithDefault 0 (fromIntegral a) . mem

sharedStoreByte :: (MonadState CPU m) => Word32 -> Word32 -> m ()
sharedStoreByte a w = modify' $ \cpu ->
  cpu {mem = M.insert (fromIntegral a) (fromIntegral $ w .&. 0xFF) (mem cpu)}

---------------------------------------------------------------------------------

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
trapECallM = 11
trapBreakpointM = 3
trapLoadMisaligned = 4
trapStoreMisaligned = 6

trapInstrMisaligned, trapIllegalInstr :: Word32
trapInstrMisaligned = 0
trapIllegalInstr = 2

clearTrapState :: (MonadCPU m) => m ()
clearTrapState = do
  setCSR 0x342 0 -- mcause
  setCSR 0x341 0 -- mepc

mkRegister :: Int -> Maybe Register
mkRegister n
  | n >= 0 && n < 32 = Just (Reg n)
  | otherwise = Nothing

entryPoint :: Word32
entryPoint = 0x0

stackTop :: Word32
stackTop = 0x7FFFFFFF -- ~ 2GB

emptyCPU :: CPU
emptyCPU =
  CPU
    { pc = entryPoint,
      regs = V.replicate 32 0 // [(2, stackTop)],
      csrs = M.empty,
      mem = M.empty,
      cycles = 0,
      status = Paused,
      heapTop = 0x20000000,
      fileMap = M.empty,
      nextFD = 3,
      outputBuffer = emptyOutput,
      systemLog = [],
      inputBuffer = Nothing
    }

incPC :: (MonadCPU m) => m ()
incPC = do
  current <- getPC
  setPC (current + 4)

extractByte :: Word32 -> Int -> Word8
extractByte w n = fromIntegral $ (w `shiftR` (n * 8)) .&. 0xFF

storeHalf :: (MonadCPU m) => Word32 -> Word32 -> m ()
storeHalf a w = do
  storeByte a (w .&. 0xFF) -- LSB
  storeByte (a + 1) (w `shiftR` 8) -- Next byte

storeWord :: (MonadCPU m) => Word32 -> Word32 -> m ()
storeWord a w = do
  storeHalf a (w .&. 0xFFFF) -- Lower half
  storeHalf (a + 2) (w `shiftR` 16) -- Upper half

loadHalf :: (MonadCPU m) => Word32 -> m Word16
loadHalf a = do
  b0 <- loadByte a
  b1 <- loadByte $ a + 1
  return $ fromIntegral b0 .|. (fromIntegral b1 `shiftL` 8)

loadWord :: (MonadCPU m) => Word32 -> m Word32
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

takeTrap :: (MonadCPU m) => Word32 -> Word32 -> Word32 -> m PCUpdate
takeTrap causeCode currentPC tval = do
  setCSR mepc currentPC
  setCSR mcause causeCode
  setCSR mtval tval
  handlerAddr <- getCSR mtvec

  let target = if handlerAddr == 0 then 0x80000000 else handlerAddr

  case causeCode of
    0 -> logFault (EInstrMisaligned currentPC tval)
    2 -> logFault (EIllegalInstruction currentPC tval)
    4 -> logFault (ELoadMisaligned currentPC tval)
    6 -> logFault (EStoreMisaligned currentPC tval)
    _ -> return ()

  return $ Jump target
  where
    mepc = 0x341
    mcause = 0x342
    mtval = 0x343
    mtvec = 0x305
