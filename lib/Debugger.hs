module Debugger where
import CPU
import Types
import Control.Monad.State
import Machine (CPU (..), RunStatus (..), Emulator, getCSR, trapBreakpointM)
import Control.Monad (when)
import Text.Printf (printf)
import qualified Data.IntMap.Strict as M
import Data.Word (Word32)
import qualified Data.Vector as V
import Data.Int (Int32)

data Debugger = Debugger 
    { past      :: [CPU]
    , current   :: CPU
    , future    :: [CPU]
    }

initDebugger :: [CPU] -> Debugger
initDebugger [] = error "Trace cannot be empty"
initDebugger (c:cs) = Debugger
    { past    = []
    , current = c
    , future  = cs 
    }

initDebuggerAtEnd :: [CPU] -> Debugger
initDebuggerAtEnd [] = error "Trace cannot be empty"
initDebuggerAtEnd t =
    let r = reverse t
    in case r of
        (s:ss) -> Debugger
            { past    = ss
            , current = s
            , future  = []
            }
        _     -> error "unreachable"

stepForward :: Debugger -> Debugger
stepForward dbg@(Debugger _ _ []) = dbg
stepForward (Debugger p c (f:fs)) = Debugger (c:p) f fs

stepBack :: Debugger -> Debugger
stepBack dbg@(Debugger [] _ _) = dbg
stepBack (Debugger (p:ps) c f) = Debugger ps p (c:f)

rewind :: Debugger -> Debugger
rewind dbg = case past dbg of
    [] -> dbg
    _  -> rewind (stepBack dbg)

loop :: [CPU] -> CPU -> IO [CPU]
loop acc curr = do
    (running, next) <- runStateT step curr
    if running
        then loop (next : acc) next
        else return (reverse (next : acc))

resumeTrace :: CPU -> IO [CPU]
resumeTrace currentCpu = 
    loop [currentCpu] currentCpu

runTrace :: Program -> CPU -> IO [CPU]
runTrace prog startCPU = do
    cpuReady <- execStateT (loadProgram prog) startCPU
    loop [cpuReady] cpuReady

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
