module Main where

import Parser (parse)
import Assembler (assemble)
import Text.Printf (printf)
import Linker (resolve, execProgram)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Debugger 
import Machine (emptyCPU, cycles)

formatFreq :: Double -> String
formatFreq hz
    | hz > 1000000000 = printf "%.2f GHz" (hz / 1000000000)
    | hz > 1000000    = printf "%.2f MHz" (hz / 1000000)
    | hz > 1000       = printf "%.2f kHz" (hz / 1000)
    | otherwise       = printf "%.0f Hz" hz

program :: String
program = unlines
    [ ".data"
    , "filename: .asciz \"riscv_output.txt\""
    , "message:  .asciz \"Hello from the RISC-V Emulator!\\n\""
    , ""
    , ".text"
    , "main:"
    , "    # 1. sys_openat(AT_FDCWD, filename, O_WRONLY)"
    , "    li a0, -100       # dirfd (ignored)"
    , "    la a1, filename   # pointer to filename string"
    , "    li a2, 1          # 1 = Write mode"
    , "    li a7, 56         # syscall 56: sys_openat"
    , "    ecall"
    , "    mv s0, a0         # Save the new file descriptor in s0"
    , ""
    , "    # 2. sys_write(fd, message, 32)"
    , "    mv a0, s0         # File descriptor"
    , "    la a1, message    # pointer to message"
    , "    li a2, 32         # length of message"
    , "    li a7, 64         # syscall 64: sys_write"
    , "    ecall"
    , ""
    , "    # 3. sys_close(fd)"
    , "    mv a0, s0         # File descriptor"
    , "    li a7, 57         # syscall 57: sys_close"
    , "    ecall"
    , ""
    , "    # 4. sys_exit(0)"
    , "    li a0, 0"
    , "    li a7, 93"
    , "    ecall"
    ]
 
main :: IO ()
main = do 
    case parse program of
        Left err -> print err
        Right inst -> do
            case resolve inst of
                Left err        -> putStrLn $ "ERROR: " ++ err
                Right resolved -> do
                    putStrLn "---- ASSEMBLED ---"
                    let assembled = assemble (execProgram resolved) 
                    mapM_ (putStrLn . printf "%032b") assembled 

                    putStrLn "---- EXECUTING ---"
                    start <- getCurrentTime

                    history <- runTrace resolved emptyCPU
                    let finalState = last history

                    end <- getCurrentTime
                    
                    let totalCycles = cycles finalState 
                    let timeDelta   = diffUTCTime end start 
                    let seconds     = realToFrac timeDelta :: Double
                    
                    let frequency   = if seconds > 0 
                                      then fromIntegral totalCycles / seconds
                                      else 0

                    putStrLn "---- EXECUTION STATS ----"
                    printf "Total Cycles:   %d\n" totalCycles
                    printf "Execution Time: %.4fs\n" seconds
                    printf "Emulated Speed: %s\n" (formatFreq frequency)
                    
                    putStrLn "---- LAUNCHING DEBUGGER ----"
                    let debugger = initDebuggerAtEnd history
                    runInteractive debugger
