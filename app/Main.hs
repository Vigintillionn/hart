module Main where

import Parser (parse)
import Data.Word
import qualified Data.Vector as V
import Control.Monad.State
import Assembler (assemble)
import Text.Printf (printf)
import CPU (runProgram, emptyCPU, regs)
import Data.Int (Int32)
import Linker (resolve)

viewRegisters :: V.Vector Word32 -> [Int32]
viewRegisters regs = map fromIntegral (V.toList regs)

program :: String
program = "addi x1, x0, 5     # x1 = 5\n \
          \ addi x2, x0, 1    # x2 = 0\n \
          \ loop:  # Loop start (offset -8 from the beq below?)\n \
          \ addi x1, x1, -1   # Decrement\n \
          \ bne  x1, x2, loop   # If x1 != 0, jump back 4 bytes (to the addi)"

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
                    print resolved
                    putStrLn "---- ASSEMBLED ---"
                    let assembled = assemble resolved 
                    mapM_ (putStrLn . printf "%032b") assembled 

                    let cpu = execState (runProgram resolved) emptyCPU
                    putStrLn "---- FINAL CPU ----"
                    print (viewRegisters $ regs cpu)
