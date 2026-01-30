module Debugger where
import CPU
import Types
import Control.Monad.State

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

nextState :: CPU -> CPU
nextState = execState step

traceExecution :: CPU -> [CPU]
traceExecution = iterate nextState

runTrace :: Program -> CPU -> [CPU]
runTrace prog c =
    let loadedCPU = execState (loadProgram prog) c
        fullTrace = traceExecution loadedCPU

        isHalt cpu =
            let inst = evalState fetch cpu
            in  inst == 0

    in takeUntil isHalt fullTrace
    where
        takeUntil :: (a -> Bool) -> [a] -> [a]
        takeUntil _ [] = []
        takeUntil p (x:xs)
            | p x       = [x]
            | otherwise = x : takeUntil p xs
