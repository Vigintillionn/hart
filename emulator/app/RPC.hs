{-# LANGUAGE OverloadedStrings #-}

module RPC (runRPC) where

import Assembler (assembleSome)
import CPU (loadProgram, step)
import Control.Monad (when)
import Control.Monad.State.Strict (execStateT, modify, runStateT)
import Data.Aeson
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.IntMap.Strict qualified as M
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Data.Sequence qualified as Seq
import Data.Word (Word32)
import Debugger (Debugger (..), atBreakpoint, disassemble, initDebugger, initDebuggerAtEnd, isAtBreakpoint, resumeTrace, rewind, stepBack, stepForward)
import Error (EmulatorError (..), Severity (..))
import Linker (Executable (..), resolve)
import Machine (CPU (..), Emulator (..), MonadCPU (..), RunStatus (..), appendOutput, clearTrapState, emptyCPU, incPC, outputDelta, signedRegs)
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
  | ResStateDelta CPU CPU
  | ResLoaded CPU [(Word32, Int)] [(Word32, String)] [(Word32, Word32)]
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
  toJSON (ResStateDelta old new) =
    object
      [ "type" .= ("state_delta" :: String),
        "pc" .= pc new,
        "regs" .= signedRegs new,
        "csrs" .= csrs new,
        "cycles" .= cycles new,
        "status" .= status new,
        "heapTop" .= heapTop new,
        "systemLog" .= reverse (systemLog new),
        -- only the bytes whose value differs from (or is new since) the base
        "memDelta" .= M.toList (M.filterWithKey changed (mem new)),
        "outputAppend" .= outputDelta (outputBuffer old) (outputBuffer new)
      ]
    where
      changed addr v = M.lookup addr (mem old) /= Just v
  toJSON (ResLoaded cpu smap dmap cmap) =
    object
      [ "type" .= ("loaded" :: String),
        "state" .= cpu,
        "sourceMap" .= smap,
        "disasmMap" .= dmap,
        "codeMap" .= cmap
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

sendState :: Maybe CPU -> Bool -> CPU -> IO (Maybe CPU)
sendState mLast forceFull c = do
  case mLast of
    Just old | not forceFull -> sendResponse (ResStateDelta old c)
    _ -> sendResponse (ResState c)
  return (Just c)

runRPC :: FilePath -> IO ()
runRPC _ = do
  sendLog Info "EMU" "Backend ready. Awaiting code."
  let emptyDbg = Debugger Seq.empty emptyCPU Seq.empty
  rpcLoop IntSet.empty Nothing emptyDbg

compileAndLoad :: String -> IO (Maybe (Debugger, [(Word32, Int)], [(Word32, String)], [(Word32, Word32)]))
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
          let prog = execProgram executable
              srcMap = execSourceMap executable
              n = length prog
          if n /= length srcMap
            then do
              sendResponse $
                ResError
                  ( "Internal error: instruction count ("
                      ++ show n
                      ++ ") does not match source-map size ("
                      ++ show (length srcMap)
                      ++ ")"
                  )
              return Nothing
            else do
              readyCpu <- execStateT (runEmulator $ loadProgram executable) emptyCPU
              sendLog Info "BUILD" ("Loaded " ++ show n ++ " instruction" ++ (if n == 1 then "" else "s") ++ " at 0x0")
              let disasmMap =
                    zipWith
                      (\instr (addr, _) -> (addr, disassemble instr))
                      prog
                      srcMap
              let codeMap =
                    zipWith
                      (\instr (addr, _) -> (addr, assembleSome instr))
                      prog
                      srcMap
              return $ Just (initDebugger (Seq.singleton readyCpu), srcMap, disasmMap, codeMap)

rpcLoop :: IntSet -> Maybe CPU -> Debugger -> IO ()
rpcLoop bps lastSent dbg = do
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
              rpcLoop bps lastSent dbg
            Just CmdQuit -> return ()
            Just (CmdSetBreakpoints addrs) ->
              rpcLoop (IntSet.fromList (map fromIntegral addrs)) lastSent dbg
            Just CmdPause -> do
              if status c == Running
                then do
                  let cPaused = c {status = Paused}
                  let newDbg = dbg {current = cPaused}
                  lastSent' <- sendState lastSent False cPaused
                  rpcLoop bps lastSent' newDbg
                else rpcLoop bps lastSent dbg
            Just (CmdLoad sourceCode) -> do
              mNewDbg <- compileAndLoad sourceCode
              case mNewDbg of
                Nothing -> rpcLoop bps lastSent dbg
                Just (newDbg, smap, dmap, cmap) -> do
                  -- a freshly loaded program is a full snapshot and the new base
                  sendResponse (ResLoaded (current newDbg) smap dmap cmap)
                  rpcLoop bps (Just (current newDbg)) newDbg
            Just CmdRun -> do
              when (status c /= Halted) $
                sendLog Info "EXEC" ("Starting execution from 0x" ++ showHex (pc c) "")
              executeRun bps lastSent dbg
            Just CmdStepFwd -> do
              if not (Seq.null (future dbg))
                then do
                  let nextDbg = stepForward dbg
                  lastSent' <- sendState lastSent False (current nextDbg)
                  rpcLoop bps lastSent' nextDbg
                else do
                  let c = current dbg
                  if status c == Halted
                    then do
                      lastSent' <- sendState lastSent False c
                      rpcLoop bps lastSent' dbg
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
                          lastSent' <- sendState lastSent False steppedState
                          rpcLoop bps lastSent' newDbg
                        else do
                          startState <- execStateT (runEmulator $ setStatus Running) c
                          (_, nextState) <- runStateT (runEmulator step) startState
                          let finalState =
                                if status nextState == Running
                                  then nextState {status = Paused}
                                  else nextState
                          let newDbg = dbg {past = past dbg Seq.|> c, current = finalState, future = Seq.Empty}
                          lastSent' <- sendState lastSent False finalState
                          rpcLoop bps lastSent' newDbg
            Just CmdStepBack -> do
              let prevDbg = stepBack dbg
              -- backward move: memory may shrink, so send a full snapshot
              lastSent' <- sendState lastSent True (current prevDbg)
              rpcLoop bps lastSent' prevDbg
            Just CmdRewind -> do
              let startDbg = rewind dbg
              lastSent' <- sendState lastSent True (current startDbg)
              rpcLoop bps lastSent' startDbg
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

                  lastSent1 <- sendState lastSent False startState

                  newTrace <- resumeTrace Nothing bps (atBreakpoint bps startState) startState

                  let fullTrace = past dbg <> newTrace
                  let newDbg = initDebuggerAtEnd fullTrace

                  let cFinal = current newDbg
                  lastSent2 <- sendState lastSent1 False cFinal
                  when (status cFinal == WaitingForInput) (sendResponse ResNeedInput)
                  rpcLoop bps lastSent2 newDbg
                else do
                  sendResponse (ResError "Emulator is not waiting for input.")
                  rpcLoop bps lastSent dbg
        else executeRun bps lastSent dbg

executeRun :: IntSet -> Maybe CPU -> Debugger -> IO ()
executeRun bps lastSent dbg = do
  let c = current dbg
  if status c == Halted
    then do
      lastSent' <- sendState lastSent False c
      rpcLoop bps lastSent' dbg
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

      lastSent1 <- sendState lastSent False startState
      newTrace <- resumeTrace Nothing bps (atBreakpoint bps startState) startState

      let fullTrace = past dbg <> newTrace
      let newDbg = initDebuggerAtEnd fullTrace

      let cFinal = current newDbg
      lastSent2 <- sendState lastSent1 False cFinal
      when (status cFinal == WaitingForInput) (sendResponse ResNeedInput)
      rpcLoop bps lastSent2 newDbg
