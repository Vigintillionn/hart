module Kernel (handleSyscall) where
import Data.Word (Word32)
import Machine
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8

handleSyscall :: MonadCPU m => m PCUpdate
handleSyscall = do
    syscall <- getReg a7 
    
    case syscall of
        64 -> do -- sys_write 
            ptr <- getReg a0 -- fd, for now we just assume stdout 
            ptrAddr <- getReg a1 -- buffer pointer 
            len <- getReg a2 -- length 
            
            str <- readString ptrAddr (fromIntegral len)
            consoleLog str 
            
            return Advance
        93 -> do -- sys_exit 
            code <- getReg a0 
            consoleLog $ "\nProgram exited with code: " ++ show code
            return Terminate 
            
        _ -> do
            consoleLog $ "Unknown Syscall: " ++ show a7
            return Advance

readString :: MonadCPU m => Word32 -> Int -> m String
readString addr len = do
    bytes <- mapM (\i -> loadByte (addr + fromIntegral i)) [0 .. len - 1]
    return $ C8.unpack $ BS.pack bytes
