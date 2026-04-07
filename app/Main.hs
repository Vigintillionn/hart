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
    , "my_text: .string \"Hello World!\\n\""
    , ""
    , ".text"
    , "main:"
    , "    # 1. Print the string"
    , "    li a0, 1          # fd = 1 (stdout)"
    , "    la a1, my_text    # buffer address"
    , "    li a2, 14          # length of \"Hello\\n\""
    , "    li a7, 64         # syscall 64 (sys_write)"
    , "    ecall"
    , ""
    , "    # 2. Exit gracefully"
    , "    li a0, 0          # exit code 0"
    , "    li a7, 93         # syscall 93 (sys_exit)"
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
