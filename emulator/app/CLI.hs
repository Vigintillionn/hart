module CLI (runCLI) where

import Parser (parse)
import Linker (resolve)
import Machine (emptyCPU)
import Debugger ( runInteractive, runTrace, initDebuggerAtEnd )
import Render (renderAssemblyError, renderLinkError)
import Text.Printf (printf)

formatFreq :: Double -> String
formatFreq hz
    | hz > 1000000000 = printf "%.2f GHz" (hz / 1000000000)
    | hz > 1000000    = printf "%.2f MHz" (hz / 1000000)
    | hz > 1000       = printf "%.2f kHz" (hz / 1000)
    | otherwise       = printf "%.0f Hz" hz

-- | Run the interactive CLI. @maxCycles@ bounds how many cycles the program
-- may execute before it is force-halted (guards against infinite loops); a
-- value @<= 0@ means unbounded.
runCLI :: Int -> FilePath -> IO ()
runCLI maxCycles filepath = do
    sourceCode <- readFile filepath

    let cycleLimit = if maxCycles <= 0 then Nothing else Just maxCycles

    case parse sourceCode of
        Left err -> putStrLn $ "Parse error: " ++ renderAssemblyError err
        Right inst -> case resolve inst of
            Left err        -> putStrLn $ "Link error: " ++ renderLinkError err
            Right resolved -> do
                putStrLn "---- EXECUTING ---"
--                start <- getCurrentTime

                trace <- runTrace cycleLimit resolved emptyCPU
--                let finalState = last history
--
--                end <- getCurrentTime
--                    
--                let totalCycles = cycles finalState 
--                let timeDelta   = diffUTCTime end start 
--                let seconds     = realToFrac timeDelta :: Double
--                    
--                let frequency   = if seconds > 0 
--                                  then fromIntegral totalCycles / seconds
--                                  else 0
--
--                putStrLn "---- EXECUTION STATS ----"
--                printf "Total Cycles:   %d\n" totalCycles
--                printf "Execution Time: %.4fs\n" seconds
--                printf "Emulated Speed: %s\n" (formatFreq frequency)

                putStrLn "---- LAUNCHING DEBUGGER ----"
                let debugger = initDebuggerAtEnd trace
                runInteractive cycleLimit debugger
