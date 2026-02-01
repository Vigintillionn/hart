module Debugger where
import CPU
import Types
import Control.Monad.State
import Machine (CPU)

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

