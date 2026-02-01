module Kernel (handleSyscall) where
import Data.Word (Word32)
import Types
import Machine
import Control.Monad.State
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8

handleSyscall :: Emulator PCUpdate
handleSyscall = do
    syscall <- getReg a7 
    
    case syscall of
        64 -> do -- sys_write 
            ptr <- getReg a0 -- fd, for now we just assume stdout 
            ptrAddr <- getReg a1 -- buffer pointer 
            len <- getReg a2 -- length 
            
            str <- readString ptrAddr (fromIntegral len)
            liftIO $ putStr str 
            
            return Advance
        93 -> do -- sys_exit 
            code <- getReg a0 
            liftIO $ putStrLn $ "\nProgram exited with code: " ++ show code
            return Terminate 
            
        _ -> do
            liftIO $ putStrLn $ "Unknown Syscall: " ++ show a7
            return Advance

readString :: Word32 -> Int -> Emulator String
readString addr len = do
    bytes <- mapM (\i -> loadByte (addr + fromIntegral i)) [0 .. len - 1]
    return $ C8.unpack $ BS.pack bytes
