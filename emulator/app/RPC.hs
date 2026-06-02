{-# LANGUAGE OverloadedStrings #-}

module RPC (runRPC) where

import CPU (loadProgram, step)
import Control.Monad (when)
import Control.Monad.State.Strict (execStateT, modify, runStateT)
import Data.Aeson
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Data.Sequence qualified as Seq
import Data.Word (Word32)
import Debugger (Debugger (..), atBreakpoint, disassemble, initDebugger, initDebuggerAtEnd, isAtBreakpoint, resumeTrace, rewind, stepBack, stepForward)
import Error (EmulatorError (..), Severity (..))
import Linker (Executable (..), resolve)
import Machine (CPU (..), Emulator (..), MonadCPU (..), RunStatus (..), appendOutput, clearTrapState, emptyCPU, incPC)
import Numeric (showHex)
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
  | CmdSetBreakpoints [Word32]
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
      "set_breakpoints" -> CmdSetBreakpoints <$> v .: "data"
      "quit" -> return CmdQuit
      _ -> fail "Unknown command"

data Response
  = ResState CPU
  | ResLoaded CPU [(Word32, Int)] [(Word32, String)]
  | -- | RPC/protocol-level message (not an emulated-program fault)
    ResError String
  | -- | a typed emulator fault (parse/link/decode/runtime)
    ResFault EmulatorError
  | -- | transient pipeline/progress feedback: severity, tag, message
    ResLog Severity String String
  | ResNeedInput

instance ToJSON Response where
  toJSON (ResState cpu) =
    object
      [ "type" .= ("state" :: String),
        "data" .= cpu
      ]
  toJSON (ResLoaded cpu smap dmap) =
    object
      [ "type" .= ("loaded" :: String),
        "state" .= cpu,
        "sourceMap" .= smap,
        "disasmMap" .= dmap
      ]
  toJSON (ResError msg) =
    object
      [ "type" .= ("error" :: String),
        "source" .= ("rpc" :: String),
        "message" .= msg
      ]
  toJSON (ResFault err) =
    object
      [ "type" .= ("error" :: String),
        "source" .= ("emulator" :: String),
        "error" .= err
      ]
  toJSON (ResLog sev tag msg) =
    object
      [ "type" .= ("log" :: String),
        "severity" .= sev,
        "tag" .= tag,
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

sendLog :: Severity -> String -> String -> IO ()
sendLog sev tag = sendResponse . ResLog sev tag

runRPC :: FilePath -> IO ()
runRPC _ = do
  sendLog Info "EMU" "Backend ready. Awaiting code."
  let emptyDbg = Debugger Seq.empty emptyCPU Seq.empty
  rpcLoop IntSet.empty emptyDbg

compileAndLoad :: String -> IO (Maybe (Debugger, [(Word32, Int)], [(Word32, String)]))
compileAndLoad sourceCode = do
  sendLog Info "BUILD" "Compiling..."
  case parse sourceCode of
    Left err -> do
      sendResponse $ ResFault (EParse err)
      return Nothing
    Right parsed -> do
      sendLog Info "BUILD" "Linking..."
      case resolve parsed of
        Left err -> do
          sendResponse $ ResFault (ELink err)
          return Nothing
        Right executable -> do
          readyCpu <- execStateT (runEmulator $ loadProgram executable) emptyCPU
          let n = length (execProgram executable)
          sendLog Info "BUILD" ("Loaded " ++ show n ++ " instruction" ++ (if n == 1 then "" else "s") ++ " at 0x0")
          let disasmMap =
                zipWith
                  (\instr (addr, _) -> (addr, disassemble instr))
                  (execProgram executable)
                  (execSourceMap executable)
          return $ Just (initDebugger (Seq.singleton readyCpu), execSourceMap executable, disasmMap)

rpcLoop :: IntSet -> Debugger -> IO ()
rpcLoop bps dbg = do
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
              rpcLoop bps dbg
            Just CmdQuit -> return ()
            Just (CmdSetBreakpoints addrs) ->
              rpcLoop (IntSet.fromList (map fromIntegral addrs)) dbg
            Just CmdPause -> do
              if status c == Running
                then do
                  let cPaused = c {status = Paused}
                  let newDbg = dbg {current = cPaused}
                  sendResponse (ResState cPaused)
                  rpcLoop bps newDbg
                else rpcLoop bps dbg
            Just (CmdLoad sourceCode) -> do
              mNewDbg <- compileAndLoad sourceCode
              case mNewDbg of
                Nothing -> rpcLoop bps dbg
                Just (newDbg, smap, dmap) -> do
                  sendResponse (ResLoaded (current newDbg) smap dmap)
                  rpcLoop bps newDbg
            Just CmdRun -> do
              when (status c /= Halted) $
                sendLog Info "EXEC" ("Starting execution from 0x" ++ showHex (pc c) "")
              executeRun bps dbg
            Just CmdStepFwd -> do
              if not (Seq.null (future dbg))
                then do
                  let nextDbg = stepForward dbg
                  sendResponse (ResState $ current nextDbg)
                  rpcLoop bps nextDbg
                else do
                  let c = current dbg
                  if status c == Halted
                    then do
                      sendResponse (ResState c)
                      rpcLoop bps dbg
                    else do
                      atBreak <- isAtBreakpoint c
                      if atBreak
                        then do
                          steppedState <-
                            execStateT
                              ( runEmulator $ do
                                  incPC
                                  clearTrapState
                                  setStatus Paused
                              )
                              c
                          let newDbg = dbg {past = past dbg Seq.|> c, current = steppedState, future = Seq.Empty}
                          sendResponse (ResState steppedState)
                          rpcLoop bps newDbg
                        else do
                          startState <- execStateT (runEmulator $ setStatus Running) c
                          (_, nextState) <- runStateT (runEmulator step) startState
                          let finalState =
                                if status nextState == Running
                                  then nextState {status = Paused}
                                  else nextState
                          let newDbg = dbg {past = past dbg Seq.|> c, current = finalState, future = Seq.Empty}
                          sendResponse (ResState finalState)
                          rpcLoop bps newDbg
            Just CmdStepBack -> do
              let prevDbg = stepBack dbg
              sendResponse (ResState $ current prevDbg)
              rpcLoop bps prevDbg
            Just CmdRewind -> do
              let startDbg = rewind dbg
              sendResponse (ResState $ current startDbg)
              rpcLoop bps startDbg
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

                  newTrace <- resumeTrace bps (atBreakpoint bps startState) startState

                  let fullTrace = past dbg <> newTrace
                  let newDbg = initDebuggerAtEnd fullTrace

                  let cFinal = current newDbg
                  if status cFinal == WaitingForInput
                    then do
                      sendResponse (ResState cFinal)
                      sendResponse ResNeedInput
                      rpcLoop bps newDbg
                    else do
                      sendResponse (ResState cFinal)
                      rpcLoop bps newDbg
                else do
                  sendResponse (ResError "Emulator is not waiting for input.")
                  rpcLoop bps dbg
        else executeRun bps dbg

executeRun :: IntSet -> Debugger -> IO ()
executeRun bps dbg = do
  let c = current dbg
  if status c == Halted
    then do
      sendResponse (ResState c)
      rpcLoop bps dbg
    else do
      atBreak <- isAtBreakpoint c
      startState <-
        execStateT
          ( runEmulator $ do
              when atBreak $ do
                incPC
                clearTrapState
              setStatus Running
          )
          c

      sendResponse (ResState startState)
      newTrace <- resumeTrace bps (atBreakpoint bps startState) startState

      let fullTrace = past dbg <> newTrace
      let newDbg = initDebuggerAtEnd fullTrace

      let cFinal = current newDbg
      if status cFinal == WaitingForInput
        then do
          sendResponse (ResState cFinal)
          sendResponse ResNeedInput
          rpcLoop bps newDbg
        else do
          sendResponse (ResState cFinal)
          rpcLoop bps newDbg
