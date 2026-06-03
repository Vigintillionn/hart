module Kernel (handleSyscall) where

import Control.Monad (zipWithM_)
import Data.Bits ((.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as C8
import Data.Word (Word32)
import Error (EmulatorError (..), Notice (..))
import Machine

handleSyscall :: (MonadCPU m) => m PCUpdate
handleSyscall = do
  syscall <- getReg a7

  case syscall of
    1 -> do
      -- print_int
      val <- getReg a0
      consolePrint $ show (fromIntegral val :: Int)
      return Advance
    4 -> do
      -- print_string
      ptr <- getReg a0
      str <- readCString ptr
      consolePrint str
      return Advance
    5 -> do
      -- read_int
      mInput <- getInputBuffer
      case mInput of
        Nothing -> return RequestInput
        Just input -> do
          let val = case reads input of
                [(n, _)] -> n
                _ -> 0
          setReg a0 val
          clearInputBuffer
          return Advance
    8 -> do
      -- read_string
      bufAddr <- getReg a0
      maxLen <- getReg a1
      mInput <- getInputBuffer
      case mInput of
        Nothing -> return RequestInput
        Just input -> do
          let toWrite = take (fromIntegral maxLen - 1) (input ++ "\n")
          let bytes = map (fromIntegral . fromEnum) toWrite ++ [0]
          zipWithM_ (\offset b -> storeByte (bufAddr + offset) b) [0 ..] bytes
          clearInputBuffer
          return Advance
    10 -> do
      -- exit
      consolePrintLn "Program exited normally"
      logNotice ProgramExitedNormally
      return Terminate
    11 -> do
      -- print_char
      charVal <- getReg a0
      consolePrint [toEnum (fromIntegral (charVal .&. 0xFF))]
      return Advance
    56 -> do
      -- sys_openat
      _ <- getReg a0 -- dirfd
      ptr <- getReg a1 -- pointer to filename string
      flags <- getReg a2 -- 0 = read, 1 = write, 2 = read/write
      path <- readCString ptr
      fd <- openHostFile path (fromIntegral flags)
      setReg a0 (fromIntegral fd)
      return Advance
    57 -> do
      -- sys_close
      fd <- getReg a0
      res <- closeHostFile (fromIntegral fd)
      setReg a0 (fromIntegral res)
      return Advance
    63 -> do
      -- sys_read
      fd <- getReg a0
      ptrAddr <- getReg a1
      len <- getReg a2

      if fd == 0
        then do
          mInput <- getInputBuffer
          case mInput of
            Nothing -> return RequestInput
            Just input -> do
              let toWrite = take (fromIntegral len) (input ++ "\n")
              let bytes = map (fromIntegral . fromEnum) toWrite
              zipWithM_ (\offset b -> storeByte (ptrAddr + offset) b) [0 ..] bytes
              setReg a0 (fromIntegral $ length bytes)
              clearInputBuffer
              return Advance
        else do
          bytes <- readHostFile (fromIntegral fd) (fromIntegral len)
          if null bytes
            then setReg a0 0
            else do
              zipWithM_ (\offset b -> storeByte (ptrAddr + offset) (fromIntegral b)) [0 ..] bytes
              setReg a0 (fromIntegral $ length bytes)
          return Advance
    64 -> do
      -- sys_write
      fd <- getReg a0
      ptrAddr <- getReg a1
      len <- getReg a2

      if fd == 1 || fd == 2
        then do
          str <- readString ptrAddr (fromIntegral len)
          consolePrint str

          setReg a0 len
        else do
          bytes <- mapM (\i -> loadByte (ptrAddr + i)) (take (fromIntegral len) [0 ..])
          res <- writeHostFile (fromIntegral fd) bytes
          setReg a0 (fromIntegral res)

      return Advance
    93 -> do
      -- sys_exit
      code <- getReg a0
      consolePrintLn $ "Program exited with code: " ++ show code
      logNotice (ProgramExited code)
      return Terminate
    214 -> do
      -- sys_brk
      requestedAddr <- getReg a0
      currentBreak <- getHeapTop
      currentSP <- getReg sp

      if requestedAddr == 0
        then
          setReg a0 currentBreak
        else
          if requestedAddr >= currentSP
            then do
              -- growing into (or past) the stack
              pc <- getPC
              logFaultAt pc (EOutOfMemory requestedAddr)
              setReg a0 currentBreak
            else
              if requestedAddr < heapBase
                then -- refuse to move the break below the heap origin
                  setReg a0 currentBreak
                else do
                  setHeapTop requestedAddr
                  setReg a0 requestedAddr

      return Advance
    _ -> do
      pc <- getPC
      logFaultAt pc (EUnknownSyscall pc syscall)
      return Advance

readString :: (MonadCPU m) => Word32 -> Int -> m String
readString addr len = do
  bytes <- mapM (\i -> loadByte (addr + fromIntegral i)) [0 .. len - 1]
  return $ C8.unpack $ BS.pack bytes

readCString :: (MonadCPU m) => Word32 -> m String
readCString addr = do
  b <- loadByte addr
  if b == 0
    then return ""
    else do
      rest <- readCString (addr + 1)
      return (toEnum (fromIntegral b) : rest)
