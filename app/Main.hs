module Main where

import Parser (parse)
import Data.Word
import qualified Data.Vector as V
import Control.Monad.State
import Assembler (assemble)
import Text.Printf (printf)
import CPU (runProgram, emptyCPU, regs, cycles)
import Data.Int (Int32)
import Linker (resolve)
import Data.Time.Clock (getCurrentTime, diffUTCTime)

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

main :: IO ()
main = do 
    case parse program of
        Left err -> print err
        Right inst -> do
            putStrLn "---- AST PARSED ---"
            print inst

            putStrLn "---- LINKED ----"
            case resolve inst of
                Left err       -> putStrLn $ "ERROR: " ++ err
                Right resolved -> do
                    start <- getCurrentTime

                    print resolved
                    putStrLn "---- ASSEMBLED ---"
                    let assembled = assemble resolved 
                    mapM_ (putStrLn . printf "%032b") assembled 

                    let cpu = execState (runProgram resolved) emptyCPU

                    end <- getCurrentTime
                    
                    let totalCycles = cycles cpu 
                    let timeDelta   = diffUTCTime end start 
                    let seconds     = realToFrac timeDelta :: Double
                    
                    let frequency   = if seconds > 0 
                                      then fromIntegral totalCycles / seconds
                                      else 0

                    putStrLn "---- EXECUTION STATS ----"
                    printf "Total Cycles:   %d\n" totalCycles
                    printf "Execution Time: %.4fs\n" seconds
                    printf "Emulated Speed: %s\n" (formatFreq frequency)
                    
                    putStrLn "---- FINAL REGISTERS ----"
                    print (viewRegisters $ regs cpu)

