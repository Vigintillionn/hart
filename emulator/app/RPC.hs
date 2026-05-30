{-# LANGUAGE OverloadedStrings #-}

module RPC (runRPC) where

import CPU (loadProgram, step)
import Control.Monad (when)
import Control.Monad.State.Strict (execStateT, modify, runStateT)
import Data.Aeson
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.Sequence qualified as Seq
import Data.Word (Word32)
import Debugger (Debugger (..), initDebugger, initDebuggerAtEnd, isAtBreakpoint, resumeTrace, rewind, stepBack, stepForward)
import Linker (Executable (..), resolve)
import Machine (CPU (..), Emulator (..), MonadCPU (..), RunStatus (..), appendOutput, emptyCPU, incPC)
import Parser (parse)
import System.IO (hFlush, hReady, isEOF, stdin, stdout)

data Command
  = CmdLoad String
  | CmdRun
  | CmdPause
  | CmdStepFwd
  | CmdStepBack
  | CmdRewind
  | CmdInput String
  | CmdQuit
  deriving (Show, Eq)

instance FromJSON Command where
  parseJSON = withObject "Command" $ \v -> do
    cmd <- v .: "command"
    case cmd :: String of
      "load" -> CmdLoad <$> v .: "data"
      "run" -> return CmdRun
      "pause" -> return CmdPause
      "step_forward" -> return CmdStepFwd
      "step_back" -> return CmdStepBack
      "rewind" -> return CmdRewind
      "input" -> CmdInput <$> v .: "data"
      "quit" -> return CmdQuit
      _ -> fail "Unknown command"

data Response = ResState CPU | ResLoaded CPU [(Word32, Int)] | ResError String | ResNeedInput

instance ToJSON Response where
  toJSON (ResState cpu) =
    object
      [ "type" .= ("state" :: String),
        "data" .= cpu
      ]
  toJSON (ResLoaded cpu smap) =
    object
      [ "type" .= ("loaded" :: String),
        "state" .= cpu,
        "sourceMap" .= smap
      ]
  toJSON (ResError msg) =
    object
      [ "type" .= ("error" :: String),
        "message" .= msg
      ]
  toJSON ResNeedInput =
    object
      [ "type" .= ("need_input" :: String)
      ]

sendResponse :: Response -> IO ()
sendResponse res = do
  BL.putStrLn (encode res)
  hFlush stdout

runRPC :: FilePath -> IO ()
runRPC _ = do
  sendResponse (ResError "Backend ready. Awaiting code from Monaco...")
  let emptyDbg = Debugger Seq.empty emptyCPU Seq.empty
  rpcLoop emptyDbg

compileAndLoad :: String -> IO (Maybe (Debugger, [(Word32, Int)]))
compileAndLoad sourceCode = do
  case parse sourceCode of
    Left err -> do
      sendResponse $ ResError ("Parse Error: " ++ show err)
      return Nothing
    Right parsed -> case resolve parsed of
      Left err -> do
        sendResponse $ ResError ("Linker Error: " ++ err)
        return Nothing
      Right executable -> do
        readyCpu <- execStateT (runEmulator $ loadProgram executable) emptyCPU
        return $ Just (initDebugger (Seq.singleton readyCpu), execSourceMap executable)

rpcLoop :: Debugger -> IO ()
rpcLoop dbg = do
  eof <- isEOF
  if eof
    then return ()
    else do
      let c = current dbg
      ready <- if status c == Running then hReady stdin else return True

      if ready
        then do
          rawInput <- getLine
          case decode (BL.pack rawInput) of
            Nothing -> do
              sendResponse $ ResError ("Invalid JSON command received: " ++ rawInput)
              rpcLoop dbg
            Just CmdQuit -> return ()
            Just CmdPause -> do
              if status c == Running
                then do
                  let cPaused = c {status = Paused}
                  let newDbg = dbg {current = cPaused}
                  sendResponse (ResState cPaused)
                  rpcLoop newDbg
                else rpcLoop dbg
            Just (CmdLoad sourceCode) -> do
              mNewDbg <- compileAndLoad sourceCode
              case mNewDbg of
                Nothing -> rpcLoop dbg
                Just (newDbg, smap) -> do
                  sendResponse (ResLoaded (current newDbg) smap)
                  rpcLoop newDbg
            Just CmdRun -> executeRun dbg
            Just CmdStepFwd -> do
              if not (Seq.null (future dbg))
                then do
                  let nextDbg = stepForward dbg
                  sendResponse (ResState $ current nextDbg)
                  rpcLoop nextDbg
                else do
                  let c = current dbg
                  if status c == Halted
                    then do
                      sendResponse (ResState c)
                      rpcLoop dbg
                    else do
                      atBreak <- isAtBreakpoint c
                      startState <-
                        execStateT
                          ( runEmulator $ do
                              when atBreak incPC
                              setStatus Running
                          )
                          c
                      (_, nextState) <- runStateT (runEmulator step) startState
                      let finalState =
                            if status nextState == Running
                              then nextState {status = Paused}
                              else nextState
                      let newDbg = dbg {past = past dbg Seq.|> c, current = finalState, future = Seq.Empty}
                      sendResponse (ResState finalState)
                      rpcLoop newDbg
            Just CmdStepBack -> do
              let prevDbg = stepBack dbg
              sendResponse (ResState $ current prevDbg)
              rpcLoop prevDbg
            Just CmdRewind -> do
              let startDbg = rewind dbg
              sendResponse (ResState $ current startDbg)
              rpcLoop startDbg
            Just (CmdInput text) -> do
              let c = current dbg
              if status c == WaitingForInput
                then do
                  startState <-
                    execStateT
                      ( runEmulator $ do
                          modify $ \cpu ->
                            cpu
                              { inputBuffer = Just text,
                                status = Running,
                                outputBuffer = appendOutput (text ++ "\n") (outputBuffer cpu)
                              }
                      )
                      c

                  sendResponse (ResState startState)

                  newTrace <- resumeTrace startState

                  let fullTrace = past dbg <> newTrace
                  let newDbg = initDebuggerAtEnd fullTrace

                  let cFinal = current newDbg
                  if status cFinal == WaitingForInput
                    then do
                      sendResponse (ResState cFinal)
                      sendResponse ResNeedInput
                      rpcLoop newDbg
                    else do
                      sendResponse (ResState cFinal)
                      rpcLoop newDbg
                else do
                  sendResponse (ResError "Emulator is not waiting for input.")
                  rpcLoop dbg
        else executeRun dbg

executeRun :: Debugger -> IO ()
executeRun dbg = do
  let c = current dbg
  if status c == Halted
    then do
      sendResponse (ResState c)
      rpcLoop dbg
    else do
      atBreak <- isAtBreakpoint c
      startState <-
        execStateT
          ( runEmulator $ do
              when atBreak incPC
              setStatus Running
          )
          c

      sendResponse (ResState startState)

      newTrace <- resumeTrace startState

      let fullTrace = past dbg <> newTrace
      let newDbg = initDebuggerAtEnd fullTrace

      let cFinal = current newDbg
      if status cFinal == WaitingForInput
        then do
          sendResponse (ResState cFinal)
          sendResponse ResNeedInput
          rpcLoop newDbg
        else do
          sendResponse (ResState cFinal)
          rpcLoop newDbg
