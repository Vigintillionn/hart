module Main where

import Parser (parse)
import Assembler (assemble)
import Text.Printf (printf)
import Linker (resolve)
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
program = 

 "      # 1. Manually build the string 'ABC\\n' in memory \n\
           \      # ... (Rest of your program string) ... \n\
           \      la   x6, msg                                    \n\
           \      addi x5, x0, 65                                 \n\
           \      sb   x5, 0(x6)                                  \n\
           \      addi x5, x0, 66                                 \n\
           \      sb   x5, 1(x6)                                  \n\
           \      addi x5, x0, 67                                 \n\
           \      sb   x5, 2(x6)                                  \n\
           \      addi x5, x0, 10                                 \n\
           \      sb   x5, 3(x6)                                  \n\
           \      ebreak                                                \n\
           \      # 2. Setup Syscall Write (64)                   \n\
           \      addi x10, x0, 1                                 \n\
           \      la   x11, msg                                   \n\
           \      addi x12, x0, 4                                 \n\
           \      addi x17, x0, 64                                \n\
           \      ecall                                           \n\
           \                                                      \n\
           \      # 4. Setup Syscall Exit (93)                    \n\
           \      addi x10, x0, 0                                 \n\
           \      addi x17, x0, 93                                \n\
           \      ecall                                           \n\
           \                                                      \n\
           \msg:  nop"
 
main :: IO ()
main = do 
    case parse program of
        Left err -> print err
        Right inst -> do
            case resolve inst of
                Left err        -> putStrLn $ "ERROR: " ++ err
                Right resolved -> do
                    putStrLn "---- ASSEMBLED ---"
                    let assembled = assemble resolved 
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
