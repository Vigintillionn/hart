module Main where

import System.Environment (getArgs)
import CLI (runCLI)
import RPC (runRPC)

main :: IO ()
main = do 
    args <- getArgs
    case args of
        [filepath] -> runCLI filepath
        ["--rpc", filepath] -> runRPC filepath
        _ -> do
            putStrLn "RISC-V Emulator"
            putStrLn "Usage:"
            putStrLn "  Interactive CLI: emulator <file.s>"
            putStrLn "  RPC Daemon:      emulator --rpc <file.s>"
