module Main where

import Parser (parse)
import Data.Word
import qualified Data.Vector as V
import Control.Monad.State
import Assembler (assemble)
import Text.Printf (printf)
import CPU (runProgram, emptyCPU, regs, cycles, pc)
import Data.Int (Int32)
import Linker (resolve)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Debugger

formatFreq :: Double -> String
formatFreq hz
    | hz > 1000000000 = printf "%.2f GHz" (hz / 1000000000)
    | hz > 1000000    = printf "%.2f MHz" (hz / 1000000)
    | hz > 1000       = printf "%.2f kHz" (hz / 1000)
    | otherwise       = printf "%.0f Hz" hz

viewRegisters :: V.Vector Word32 -> [Int32]
viewRegisters regs = map fromIntegral (V.toList regs)

program :: String
program = "      addi x1, x0, 10000000 \n\
          \      addi x2, x0, 1        \n\
          \loop: sub  x1, x1, x2       \n\
          \      bne  x1, x0, loop"

runInteractive :: Debugger -> IO ()
runInteractive dbg = do
    putStrLn "\n----------------------------------------"
    
    let c = current dbg
    printf "PC: 0x%08x | Cycle: %d\n" (pc c) (cycles c)
    
    print (viewRegisters $ regs c)

    putStrLn "[p]rev, [n]ext, [r]ewind, [q]uit"
    cmd <- getLine
    case cmd of
        "p" -> runInteractive (stepBack dbg)    
        "n" -> runInteractive (stepForward dbg) 
        "r" -> runInteractive (rewind dbg)      
        "q" -> putStrLn "Exiting debugger."
        _   -> runInteractive dbg

main :: IO ()
main = do 
    case parse program of
        Left err -> print err
        Right inst -> do
            case resolve inst of
                Left err       -> putStrLn $ "ERROR: " ++ err
                Right resolved -> do
                    putStrLn "---- ASSEMBLED ---"
                    let assembled = assemble resolved 
                    mapM_ (putStrLn . printf "%032b") assembled 

                    putStrLn "---- EXECUTING ---"
                    start <- getCurrentTime

                    let history = runTrace resolved emptyCPU
                    let finalState = last history

                    finalState `seq` return ()
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

