module Main where

import Parser (parse)
import Data.Word
import qualified Data.Vector as V
import Control.Monad.State
import Assembler (assemble)
import Text.Printf (printf)
import CPU (runProgram, emptyCPU, regs)
import Data.Int (Int32)

viewRegisters :: V.Vector Word32 -> [Int32]
viewRegisters regs = map fromIntegral (V.toList regs)

program :: String
program = "addi x1, x0, 5     # x1 = 5\n \
          \ addi x2, x0, 1    # x2 = 0\n \
          \ # Loop start (offset -8 from the beq below?)\n \
          \ addi x1, x1, -1   # Decrement\n \
          \ bne  x1, x2, -4   # If x1 != 0, jump back 4 bytes (to the addi)"

main :: IO ()
main = do 
    case parse program of
        Left err -> print err
        Right inst -> do
            putStrLn "---- AST PARSED ---"
            print inst

            putStrLn "---- ASSEMBLED ---"
            let assembled = assemble inst
            mapM_ (putStrLn . printf "%032b") assembled 

            let cpu = execState (runProgram inst) emptyCPU
            putStrLn "---- FINAL CPU ----"
            print (viewRegisters $ regs cpu)
