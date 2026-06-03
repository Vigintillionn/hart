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
    _ -> case parseCliArgs defaultMaxCycles Nothing args of
      Just (limit, filepath) -> runCLI limit filepath
      Nothing -> usage

parseCliArgs :: Int -> Maybe FilePath -> [String] -> Maybe (Int, FilePath)
parseCliArgs lim (Just fp) [] = Just (lim, fp)
parseCliArgs _ Nothing [] = Nothing
parseCliArgs _ mfp (flag : n : rest)
  | flag `elem` ["--max-cycles", "-c"],
    [(v, "")] <- reads n =
      parseCliArgs v mfp rest
parseCliArgs lim Nothing (a : rest)
  | not ("-" `isPrefixOf` a) = parseCliArgs lim (Just a) rest
parseCliArgs _ _ _ = Nothing

usage :: IO ()
usage = do
  putStrLn "RISC-V Emulator"
  putStrLn "Usage:"
  putStrLn "  Interactive CLI: emulator <file.s> [--max-cycles N]"
  putStrLn "  RPC Daemon:      emulator --rpc <file.s>"
  putStrLn ""
  putStrLn
    ( "  --max-cycles N, -c N   cap execution at N cycles (default "
        ++ show defaultMaxCycles
        ++ "; 0 = unbounded)"
    )
