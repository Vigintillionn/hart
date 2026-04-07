module CLI (runCLI) where

import Parser (parse)
import Linker (resolve)
import Machine (emptyCPU)
import Debugger ( runInteractive, runTrace, initDebuggerAtEnd )
import Text.Printf (printf)

formatFreq :: Double -> String
formatFreq hz
    | hz > 1000000000 = printf "%.2f GHz" (hz / 1000000000)
    | hz > 1000000    = printf "%.2f MHz" (hz / 1000000)
    | hz > 1000       = printf "%.2f kHz" (hz / 1000)
    | otherwise       = printf "%.0f Hz" hz

runCLI :: FilePath -> IO ()
runCLI filepath = do
    sourceCode <- readFile filepath

    case parse sourceCode of
        Left err -> print err
        Right inst -> case resolve inst of
            Left err        -> putStrLn $ "ERROR: " ++ err
            Right resolved -> do
                putStrLn "---- EXECUTING ---"
--                start <- getCurrentTime

                trace <- runTrace resolved emptyCPU
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
                runInteractive debugger
