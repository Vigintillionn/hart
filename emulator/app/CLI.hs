module CLI (runCLI) where

import Debugger (initDebuggerAtEnd, runInteractive, runTrace)
import Extension (defaultExtensions)
import Linker (resolve)
import Machine (emptyCPU)
import Parser (parseWithLocs)
import Preprocess
  ( Expanded (..),
    IncludeFailure (..),
    Resolver,
    expand,
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
runCLI :: Int -> FilePath -> IO ()
runCLI maxCycles filepath = do
  sourceCode <- readFile filepath
  rootPath <- canonicalizePath filepath

  let cycleLimit = if maxCycles <= 0 then Nothing else Just maxCycles

  expanded <- expand fsResolver rootPath sourceCode
  case expanded of
    Left perr -> putStrLn $ "Include error: " ++ renderPreprocessError perr
    Right ex -> case parseWithLocs defaultExtensions (locAt ex) (expSource ex) of
      Left err -> putStrLn $ "Parse error: " ++ renderAssemblyError err
      Right inst -> case resolve inst of
        Left err -> putStrLn $ "Link error: " ++ renderLinkError err
        Right resolved -> do
          putStrLn "---- EXECUTING ---"

          trace <- runTrace cycleLimit resolved emptyCPU

          putStrLn "---- LAUNCHING DEBUGGER ----"
          let debugger = initDebuggerAtEnd trace
          runInteractive cycleLimit debugger
