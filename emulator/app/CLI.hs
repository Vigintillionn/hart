module CLI (runCLI) where

import Debugger (defaultMaxHistory, initDebuggerAtEnd, runInteractive, runTrace)
import Extension (defaultExtensions)
import Linker (resolve)
import Machine (emptyCPU)
import Parser (parseWithLocs)
import Preprocess
  ( Expanded (..),
    IncludeFailure (..),
    Resolver,
    expandMany,
    locAt,
  )
import Render (renderAssemblyError, renderLinkError, renderPreprocessError)
import System.Directory (canonicalizePath, doesFileExist)
import System.FilePath ((</>))

-- | resolve an @.include@ against the filesystem: relative to the including
-- file's directory first, then as given; the path is canonicalised so the same
-- file reached two ways is recognised as a cycle
fsResolver :: Resolver IO
fsResolver dir req = go [dir </> req, req]
  where
    go [] = pure (Left NotFound)
    go (c : cs) = do
      exists <- doesFileExist c
      if exists
        then do
          canon <- canonicalizePath c
          contents <- readFile canon
          pure (Right (canon, contents))
        else go cs

-- | Run the interactive CLI. @maxCycles@ bounds how many cycles the program
-- may execute before it is force-halted (guards against infinite loops); a
-- value @<= 0@ means unbounded.
--
-- Each file is assembled as a translation unit of its own and they are linked
-- together, in the order given.
runCLI :: Int -> [FilePath] -> IO ()
runCLI maxCycles filepaths = do
  roots <- traverse (\fp -> (,) <$> canonicalizePath fp <*> readFile fp) filepaths

  let cycleLimit = if maxCycles <= 0 then Nothing else Just maxCycles

  expanded <- expandMany fsResolver roots
  case expanded of
    Left perr -> putStrLn $ "Include error: " ++ renderPreprocessError perr
    Right ex -> case parseWithLocs defaultExtensions (locAt ex) (expSource ex) of
      Left err -> putStrLn $ "Parse error: " ++ renderAssemblyError err
      Right inst -> case resolve inst of
        Left err -> putStrLn $ "Link error: " ++ renderLinkError err
        Right resolved -> do
          putStrLn "---- EXECUTING ---"

          trace <- runTrace defaultMaxHistory cycleLimit resolved emptyCPU

          putStrLn "---- LAUNCHING DEBUGGER ----"
          let debugger = initDebuggerAtEnd defaultMaxHistory trace
          runInteractive cycleLimit debugger
