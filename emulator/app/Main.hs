module Main where

import CLI (runCLI)
import Data.List (isPrefixOf)
import RPC (runRPC)
import System.Environment (getArgs)

defaultMaxCycles :: Int
defaultMaxCycles = 10000

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("--rpc" : rest) -> case rest of
      [filepath] -> runRPC filepath
      _ -> usage
    _ -> case parseCliArgs defaultMaxCycles [] args of
      Just (limit, filepaths) -> runCLI limit filepaths
      Nothing -> usage

parseCliArgs :: Int -> [FilePath] -> [String] -> Maybe (Int, [FilePath])
parseCliArgs _ [] [] = Nothing
parseCliArgs lim fps [] = Just (lim, reverse fps)
parseCliArgs _ fps (flag : n : rest)
  | flag `elem` ["--max-cycles", "-c"],
    [(v, "")] <- reads n =
      parseCliArgs v fps rest
parseCliArgs lim fps (a : rest)
  | not ("-" `isPrefixOf` a) = parseCliArgs lim (a : fps) rest
parseCliArgs _ _ _ = Nothing

usage :: IO ()
usage = do
  putStrLn "RISC-V Emulator"
  putStrLn "Usage:"
  putStrLn "  Interactive CLI: emulator <file.s>... [--max-cycles N]"
  putStrLn "  RPC Daemon:      emulator --rpc <file.s>"
  putStrLn ""
  putStrLn
    ( "  --max-cycles N, -c N   cap execution at N cycles (default "
        ++ show defaultMaxCycles
        ++ "; 0 = unbounded)"
    )
