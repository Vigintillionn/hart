module Kernel (handleSyscall) where
import Data.Word (Word32)
import Machine
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import Data.Int (Int32)
import Control.Monad (zipWithM_)

handleSyscall :: MonadCPU m => m PCUpdate
handleSyscall = do
    syscall <- getReg a7 
    
    case syscall of
        63 -> do -- sys_read
            fd      <- getReg a0
            ptrAddr <- getReg a1
            len     <- getReg a2

            if fd == 0 then do 
                input <- consoleRead
                
                let toWrite = take (fromIntegral len) (input ++ "\n")
                let bytes = map (fromIntegral . fromEnum) toWrite
                zipWithM_ (\offset b -> storeByte (ptrAddr + offset) b) [0..] bytes
                
                setReg a0 (fromIntegral $ length bytes)
            else
                setReg a0 (fromIntegral (-1 :: Int32))
            
            return Advance
        64 -> do -- sys_write 
            fd      <- getReg a0 
            ptrAddr <- getReg a1 
            len     <- getReg a2 
            
            if fd == 1 || fd == 2 then do 
                str <- readString ptrAddr (fromIntegral len)
                consolePrint str 
                
                setReg a0 len 
            else
                setReg a0 (fromIntegral (-1 :: Int32))
            
            return Advance
        93 -> do -- sys_exit 
            code <- getReg a0 
            consolePrintLn $ "\nProgram exited with code: " ++ show code
            return Terminate 
        214 -> do -- sys_brk
            requestedAddr <- getReg a0
            currentBreak <- getHeapTop
            currentSP <- getReg sp
            
            if requestedAddr == 0 then do
                setReg a0 currentBreak
            else if requestedAddr >= currentSP then do
                consolePrintLn "\n[Kernel] sys_brk failed: Out of Memory! (Heap collided with Stack)"
                setReg a0 currentBreak
            else do
                setHeapTop requestedAddr
                setReg a0 requestedAddr
                
            return Advance
        _ -> do
            consolePrintLn $ "Unknown Syscall: " ++ show a7
            return Advance

readString :: MonadCPU m => Word32 -> Int -> m String
readString addr len = do
    bytes <- mapM (\i -> loadByte (addr + fromIntegral i)) [0 .. len - 1]
    return $ C8.unpack $ BS.pack bytes
