{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.RpcSpec (spec) where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Data.Aeson (Result (..), Value (..), decodeStrict, encode, fromJSON, object, (.=))
import Data.Aeson.Key qualified as K
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.Char (isSpace)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Process (readProcess)
import System.Random (randomRIO)
import Test.Hspec

examplesDir :: FilePath
examplesDir = "../frontend/src/lib/examples"

spec :: Spec
spec = do
  mBin <- runIO locateBin
  case mBin of
    Nothing ->
      it "RPC integration tests" $
        pendingWith
          "hart-emulator binary not found: run `cabal build` (or set HART_EMULATOR_BIN) to enable"
    Just bin -> rpcSpec bin

rpcSpec :: FilePath -> Spec
rpcSpec bin = do
  describe "startup handshake" $ do
    resp <- runIO (runSession bin [quitCmd])
    it "announces the extension catalogue" $
      hasType "extensions" resp `shouldBe` True
    it "announces the self-describing instruction reference" $
      hasType "instruction_set" resp `shouldBe` True
    it "emits a ready log line" $
      hasType "log" resp `shouldBe` True

  describe "onboarding examples run to completion" $ do
    -- welcome.s: prints "sum(1..5) = 15"
    exampleCase bin "welcome.s" [] $ \out ->
      out `shouldContain` "sum(1..5) = 15"
    -- fibonacci.s: the first ten Fibonacci numbers, space-separated
    exampleCase bin "fibonacci.s" [] $ \out ->
      out `shouldContain` "0 1 1 2 3 5 8 13 21 34"
    -- factorial.s: recursive 5! = 120
    exampleCase bin "factorial.s" [] $ \out ->
      out `shouldContain` "120"

  describe "interactive I/O (interactive.s)" $ do
    n <- runIO $ randomRIO (-46340, 46340 :: Int)

    let nStr = show n
    let squaredStr = show (n * n)
    -- the program prompts, pauses at read_int, and squares what we feed it
    exampleCase bin "interactive.s" [inputCmd nStr] $ \out -> do
      out `shouldContain` "Enter a number:"
      out `shouldContain` "Its square is: " ++ squaredStr

  describe "time-travel debugging (welcome.s)" $ do
    mSrc <- runIO (readExample "welcome.s")
    case mSrc of
      Nothing -> skip "welcome.s"
      Just src -> do
        resp <-
          runIO $
            runSession
              bin
              [loadCmd src, runCmd, stepBackCmd, stepBackCmd, rewindCmd, quitCmd]
        it "records a non-trivial execution trace" $
          maxCycles resp `shouldSatisfy` (> 0)
        it "rewinds to the start of the trace (cycle 0)" $
          (lastFullState resp >>= cyclesOf) `shouldBe` Just 0
        it "reports no faults while stepping backwards" $
          errorResponses resp `shouldBe` []

exampleCase :: FilePath -> String -> [Value] -> (String -> Expectation) -> Spec
exampleCase bin name extra checkOutput = do
  mSrc <- runIO (readExample name)
  case mSrc of
    Nothing -> skip name
    Just src -> do
      resp <- runIO (runSession bin ([loadCmd src, runCmd] ++ extra ++ [quitCmd]))
      it (name ++ ": assembles and loads with no emulator faults") $
        errorResponses resp `shouldBe` []
      it (name ++ ": produces the expected program output") $
        checkOutput (sessionOutput resp)
      it (name ++ ": halts cleanly") $
        finalStatus resp `shouldBe` Just "Halted"

skip :: String -> Spec
skip name =
  it (name ++ " (skipped: example not found)") $
    pendingWith ("could not read " ++ examplesDir ++ "/" ++ name)

runSession :: FilePath -> [Value] -> IO [Value]
runSession bin cmds = do
  let input = unlines (map (BL.unpack . encode) cmds)
  out <- readProcess bin ["--rpc", "unused"] input
  pure (mapMaybe (decodeStrict . TE.encodeUtf8 . T.pack) (lines out))

loadCmd :: String -> Value
loadCmd src = object ["command" .= ("load" :: String), "data" .= src]

runCmd, stepBackCmd, rewindCmd, quitCmd :: Value
runCmd = object ["command" .= ("run" :: String)]
stepBackCmd = object ["command" .= ("step_back" :: String)]
rewindCmd = object ["command" .= ("rewind" :: String)]
quitCmd = object ["command" .= ("quit" :: String)]

inputCmd :: String -> Value
inputCmd t = object ["command" .= ("input" :: String), "data" .= t]

look :: K.Key -> Value -> Maybe Value
look k (Object o) = KM.lookup k o
look _ _ = Nothing

asString :: Value -> Maybe String
asString (String t) = Just (T.unpack t)
asString _ = Nothing

asInt :: Value -> Maybe Int
asInt v = case fromJSON v of
  Success n -> Just n
  Error _ -> Nothing

respType :: Value -> Maybe String
respType v = look "type" v >>= asString

hasType :: String -> [Value] -> Bool
hasType t = any ((== Just t) . respType)

errorResponses :: [Value] -> [Value]
errorResponses = filter ((== Just "error") . respType)

sessionOutput :: [Value] -> String
sessionOutput = foldl step ""
  where
    step acc v = case respType v of
      Just "loaded" -> orKeep acc (look "state" v >>= look "outputBuffer" >>= asString)
      Just "state" -> orKeep acc (look "data" v >>= look "outputBuffer" >>= asString)
      Just "state_delta" -> acc ++ fromMaybe "" (look "outputAppend" v >>= asString)
      _ -> acc
    orKeep = fromMaybe

statusOf :: Value -> Maybe String
statusOf v = case respType v of
  Just "state" -> look "data" v >>= look "status" >>= asString
  Just "loaded" -> look "state" v >>= look "status" >>= asString
  Just "state_delta" -> look "status" v >>= asString
  _ -> Nothing

finalStatus :: [Value] -> Maybe String
finalStatus = lastMay . mapMaybe statusOf

cyclesOf :: Value -> Maybe Int
cyclesOf v = (look "cycles" v <|> (look "data" v >>= look "cycles")) >>= asInt

maxCycles :: [Value] -> Int
maxCycles = maximum . (0 :) . mapMaybe cyclesOf

lastFullState :: [Value] -> Maybe Value
lastFullState = lastMay . filter ((== Just "state") . respType)

lastMay :: [a] -> Maybe a
lastMay [] = Nothing
lastMay xs = Just (last xs)

readExample :: String -> IO (Maybe String)
readExample name = do
  let path = examplesDir ++ "/" ++ name
  exists <- doesFileExist path
  if exists then Just <$> readFile path else pure Nothing

locateBin :: IO (Maybe FilePath)
locateBin = do
  mEnv <- lookupEnv "HART_EMULATOR_BIN"
  case mEnv of
    Just p -> ifExists p
    Nothing -> do
      r <- try (readProcess "cabal" ["list-bin", "exe:hart-emulator"] "")
      case r of
        Right out -> ifExists (lastPath out)
        Left (_ :: SomeException) -> pure Nothing
  where
    ifExists p = do
      e <- doesFileExist p
      pure (if e then Just p else Nothing)
    lastPath = maybe "" (dropWhile isSpace) . lastMay . filter (not . null) . map trim . lines
    trim = f . f where f = reverse . dropWhile isSpace
