module Main where

import Parser (parse)
import Data.Word
import qualified Data.Vector as V
import Assembler (assemble)
import Text.Printf (printf)
import Machine (emptyCPU, regs, cycles, pc, csrs, CPU, Emulator, getCSR, RunStatus(..), status) 
import Data.Int (Int32)
import Linker (resolve)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Debugger 
import qualified Data.IntMap.Strict as M
import Types (decodeCSRName, trapBreakpointM)
import Control.Monad.State
import CPU (incrPC, fetch, step)
import Control.Monad (when)

formatFreq :: Double -> String
formatFreq hz
    | hz > 1000000000 = printf "%.2f GHz" (hz / 1000000000)
    | hz > 1000000    = printf "%.2f MHz" (hz / 1000000)
    | hz > 1000       = printf "%.2f kHz" (hz / 1000)
    | otherwise       = printf "%.0f Hz" hz

viewRegisters :: V.Vector Word32 -> [Int32]
viewRegisters regs = map fromIntegral (V.toList regs)

viewCSRs :: M.IntMap Word32 -> String
viewCSRs csrMap = 
    let validCSRs = filter (\(k,_) -> k >= 0x300) (M.toList csrMap)
    in unlines $ map fmt validCSRs
  where
    fmt (addr, val) = printf "  %s: 0x%08x" (decodeCSRName addr) val

isAtBreakpoint :: CPU -> IO Bool
isAtBreakpoint = evalStateT check
  where
    check :: Emulator Bool
    check = do
        cause <- getCSR 0x342       -- mcause
        epc   <- getCSR 0x341       -- mepc
        currentPC <- gets pc        
        return (cause == trapBreakpointM && epc == currentPC)

isHalted :: CPU -> IO Bool
isHalted c = do
    w <- evalStateT fetch c 
    return (w == 0) 

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
 
runInteractive :: Debugger -> IO ()
runInteractive dbg = do
    putStrLn "\n----------------------------------------"
    
    let c = current dbg
    printf "PC: 0x%08x | Cycle: %d\n" (pc c) (cycles c)
    
    print (viewRegisters $ regs c)
    putStrLn "CSRs:"
    putStrLn (viewCSRs $ csrs c)

    putStrLn "[p]rev, [n]ext, [c]ontinue, [r]ewind, [q]uit: " 
    cmd <- getLine
    case cmd of
        "p" -> runInteractive (stepBack dbg)    
        "n" -> case future dbg of
            (_:_) -> runInteractive (stepForward dbg)
            []    -> case status c of
                Halted -> do
                    putStrLn ">> Execution Finished. Cannot step."
                    runInteractive dbg
                _ -> do
                    atBreak <- isAtBreakpoint c
                    startState <- execStateT (do
                                    when atBreak incrPC
                                    modify $ \cpu -> cpu { status = Running }
                                  ) c
                    (_, nextState) <- runStateT step startState
                    
                    let newDbg = Debugger 
                           { past    = c : past dbg 
                           , current = nextState
                           , future  = []
                           }
                    
                    runInteractive newDbg
        "r" -> runInteractive (rewind dbg)      
        "q" -> putStrLn "Exiting debugger."
        "c" -> do
            case status c of
                Halted -> do
                    putStrLn ">> Execution Finished (Halted)."
                    runInteractive dbg
                _ -> do
                    atBreak <- isAtBreakpoint c
                    if atBreak 
                        then putStrLn ">> Resuming from breakpoint..."
                        else putStrLn ">> Resuming..."
                    startState <- execStateT (do
                                    when atBreak incrPC 
                                    modify $ \cpu -> cpu { status = Running }
                                  ) c
                    newTrace <- resumeTrace startState
                    
                    let fullTrace = reverse (past dbg) ++ newTrace
                    let newDbg = initDebuggerAtEnd fullTrace
                    
                    runInteractive newDbg
        ""  -> runInteractive dbg 
        _   -> runInteractive dbg

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
