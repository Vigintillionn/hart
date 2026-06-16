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
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (mapMaybe)
import Data.Sequence qualified as Seq
import Data.Word (Word32)
import Debugger (Debugger (..), atBreakpoint, disassemble, extendBounded, initDebugger, initDebuggerAtEnd, resumeTrace, rewind, stepBack, stepForward)
import Doc (csrCatalogue, directiveCatalogue, formatCatalogue, instructionCatalogue, pseudoCatalogue, syscallCatalogue)
import Error (EmulatorError (..), Severity (..))
import Extension
  ( ExtensionInfo (..),
    ExtensionSet,
    defaultExtensions,
    extensionCatalogue,
    extensionInfo,
    isEnabled,
    mkExtensionSet,
    readExtensionCode,
  )
import Linker (Executable (..), resolve)
import Machine (CPU (..), Emulator (..), MonadCPU (..), RunStatus (..), StopReason (..), appendOutput, emptyCPU, entryPoint, incPC, outputDelta, signedRegs)
import Numeric (showHex)
import Parser (parseWithLocs)
import Preprocess (Expanded (..), IncludeFailure (..), Resolver, expandMany, locAt)
import Render (renderPreprocessError)
import System.IO (hFlush, hReady, isEOF, stdin, stdout)

data Command
  = -- | the files available to the build (name, content) and the ordered list
    -- of entry-file names to assemble + link (the active file first); a single
    -- anonymous buffer is @[("", src)]@ with entry @[""]@.
    CmdLoad [(FilePath, String)] [FilePath]
  | CmdRun
  | CmdPause
  | CmdStepFwd
  | CmdStepBack
  | CmdRewind
  | CmdInput String
  | CmdSetBreakpoints [Word32]
  | -- | enable exactly this set of extensions (by ISA code, e.g. @["I","M"]@)
    CmdSetExtensions [String]
  | CmdGetExtensions
  | -- | request the static instruction-reference catalogue
    CmdGetInstructionSet
  | CmdQuit
  deriving (Show, Eq)

instance FromJSON Command where
  parseJSON = withObject "Command" $ \v -> do
    cmd <- v .: "command"
    case cmd :: String of
      "load" -> v .: "data" >>= parseLoad
      "run" -> return CmdRun
      "pause" -> return CmdPause
      "step_forward" -> return CmdStepFwd
      "step_back" -> return CmdStepBack
      "rewind" -> return CmdRewind
      "input" -> CmdInput <$> v .: "data"
      "set_breakpoints" -> CmdSetBreakpoints <$> v .: "data"
      "set_extensions" -> CmdSetExtensions <$> v .: "data"
      "get_extensions" -> return CmdGetExtensions
      "get_instruction_set" -> return CmdGetInstructionSet
      "quit" -> return CmdQuit
      _ -> fail "Unknown command"
    where
      -- data: {files: [{name, content}, ...], entry: [name, ...]}
      -- @entry@ is optional and defaults to every file, in the order given.
      parseLoad d = do
        objs <- d .: "files"
        files <- mapM (\o -> (,) <$> o .: "name" <*> o .: "content") objs
        entry <- d .:? "entry" .!= map fst files
        pure (CmdLoad files entry)

data Response
  = ResState CPU
  | ResStateDelta CPU CPU
  | ResLoaded CPU [(Word32, Int, FilePath)] [(Word32, String)] [(Word32, Word32)]
  | -- | RPC/protocol-level message (not an emulated-program fault)
    ResError String
  | -- | a typed emulator fault (parse/link/decode/runtime)
    ResFault EmulatorError
  | -- | transient pipeline/progress feedback: severity, tag, message
    ResLog Severity String String
  | -- | the extension catalogue and which ones are currently enabled
    ResExtensions ExtensionSet
  | -- | the static instruction-reference catalogue (formats + instructions)
    ResInstructionSet
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
  toJSON (ResExtensions exts) =
    object
      [ "type" .= ("extensions" :: String),
        "data" .= map entry extensionCatalogue
      ]
    where
      entry e =
        let i = extensionInfo e
         in object
              [ "code" .= extCode i,
                "name" .= extName i,
                "summary" .= extSummary i,
                "mandatory" .= extMandatory i,
                "enabled" .= isEnabled e exts
              ]
  toJSON ResInstructionSet =
    object
      [ "type" .= ("instruction_set" :: String),
        "formats" .= formatCatalogue,
        "instructions" .= instructionCatalogue,
        "pseudos" .= pseudoCatalogue,
        "syscalls" .= syscallCatalogue,
        "directives" .= directiveCatalogue,
        "csrs" .= csrCatalogue
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
  sendResponse (ResExtensions defaultExtensions)
  sendResponse ResInstructionSet
  let emptyDbg = Debugger Seq.empty emptyCPU Seq.empty
  rpcLoop defaultExtensions IntSet.empty Nothing emptyDbg

-- | resolve @.include@ against the files the app provided (open editor buffers), by exact name
mapResolver :: (Applicative m) => [(FilePath, String)] -> Resolver m
mapResolver files _dir req =
  pure $ case lookup req files of
    Just content -> Right (req, content)
    Nothing -> Left NotFound

compileAndLoad ::
  ExtensionSet ->
  [(FilePath, String)] ->
  [FilePath] ->
  IO (Maybe (Debugger, [(Word32, Int, FilePath)], [(Word32, String)], [(Word32, Word32)]))
compileAndLoad exts files entry = do
  -- concatenate the entry files into one unit, resolving any @.include@ against
  -- the full set of open files; provenance keeps each line tied to its file
  let entryFiles = [(n, c) | n <- entry, Just c <- [lookup n files]]
  expanded <- expandMany (mapResolver files) entryFiles
  case expanded of
    Left perr -> do
      sendResponse $ ResError (renderPreprocessError perr)
      return Nothing
    Right ex -> case parseWithLocs exts (locAt ex) (expSource ex) of
      Left err -> do
        sendResponse $ ResFault (EParse err)
        return Nothing
      Right parsed -> case resolve parsed of
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
              readyCpu <- execStateT (runEmulator $ loadProgram executable) emptyCPU {enabledExts = exts}
              let nFiles = length entryFiles
                  filesNote = if nFiles > 1 then " from " ++ show nFiles ++ " files" else ""
              sendLog Info "BUILD" ("assembled " ++ show n ++ " instruction" ++ (if n == 1 then "" else "s") ++ filesNote ++ " · entry 0x" ++ showHex entryPoint "")
              let disasmMap =
                    zipWith
                      (\instr (addr, _, _) -> (addr, disassemble instr))
                      prog
                      srcMap
              let codeMap =
                    zipWith
                      (\instr (addr, _, _) -> (addr, assembleSome instr))
                      prog
                      srcMap
              return $ Just (initDebugger (readyCpu :| []), srcMap, disasmMap, codeMap)

rpcLoop :: ExtensionSet -> IntSet -> Maybe CPU -> Debugger -> IO ()
rpcLoop exts bps lastSent dbg = do
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
              rpcLoop exts bps lastSent dbg
            Just CmdQuit -> return ()
            Just (CmdSetBreakpoints addrs) ->
              rpcLoop exts (IntSet.fromList (map fromIntegral addrs)) lastSent dbg
            Just (CmdSetExtensions codes) -> do
              let exts' = mkExtensionSet (mapMaybe readExtensionCode codes)
              sendResponse (ResExtensions exts')
              rpcLoop exts' bps lastSent dbg
            Just CmdGetExtensions -> do
              sendResponse (ResExtensions exts)
              rpcLoop exts bps lastSent dbg
            Just CmdGetInstructionSet -> do
              sendResponse ResInstructionSet
              rpcLoop exts bps lastSent dbg
            Just CmdPause -> do
              if status c == Running
                then do
                  let cPaused = c {status = Paused}
                  let newDbg = dbg {current = cPaused}
                  lastSent' <- sendState lastSent False cPaused
                  rpcLoop exts bps lastSent' newDbg
                else rpcLoop exts bps lastSent dbg
            Just (CmdLoad files entry) -> do
              mNewDbg <- compileAndLoad exts files entry
              case mNewDbg of
                Nothing -> rpcLoop exts bps lastSent dbg
                Just (newDbg, smap, dmap, cmap) -> do
                  -- a freshly loaded program is a full snapshot and the new base
                  sendResponse (ResLoaded (current newDbg) smap dmap cmap)
                  rpcLoop exts bps (Just (current newDbg)) newDbg
            Just CmdRun -> executeRun exts bps lastSent dbg
            Just CmdStepFwd -> do
              if not (Seq.null (future dbg))
                then do
                  let nextDbg = stepForward dbg
                  lastSent' <- sendState lastSent False (current nextDbg)
                  rpcLoop exts bps lastSent' nextDbg
                else do
                  if status c == Halted
                    then do
                      lastSent' <- sendState lastSent False c
                      rpcLoop exts bps lastSent' dbg
                    else
                      if stopReason c == OnEbreak
                        then do
                          steppedState <-
                            execStateT
                              ( runEmulator $ do
                                  incPC
                                  setStatus Paused
                                  setStopReason NoStop
                              )
                              c
                          let newDbg = dbg {past = past dbg Seq.|> c, current = steppedState, future = Seq.Empty}
                          lastSent' <- sendState lastSent False steppedState
                          rpcLoop exts bps lastSent' newDbg
                        else do
                          startState <- execStateT (runEmulator $ setStatus Running >> setStopReason NoStop) c
                          (_, nextState) <- runStateT (runEmulator step) startState
                          let finalState =
                                if status nextState == Running
                                  then nextState {status = Paused}
                                  else nextState
                          let newDbg = dbg {past = past dbg Seq.|> c, current = finalState, future = Seq.Empty}
                          lastSent' <- sendState lastSent False finalState
                          rpcLoop exts bps lastSent' newDbg
            Just CmdStepBack -> do
              let prevDbg = stepBack dbg
              -- backward move: memory may shrink, so send a full snapshot
              lastSent' <- sendState lastSent True (current prevDbg)
              rpcLoop exts bps lastSent' prevDbg
            Just CmdRewind -> do
              let startDbg = rewind dbg
              lastSent' <- sendState lastSent True (current startDbg)
              rpcLoop exts bps lastSent' startDbg
            Just (CmdInput text) -> do
              if status c == WaitingForInput
                then do
                  startState <-
                    execStateT
                      ( runEmulator $ do
                          modify $ \cpu ->
                            cpu
                              { inputBuffer = Just text,
                                status = Running,
                                stopReason = NoStop,
                                outputBuffer = appendOutput (text ++ "\n") (outputBuffer cpu)
                              }
                      )
                      c

                  lastSent1 <- sendState lastSent False startState

                  newTrace <- resumeTrace Nothing bps (atBreakpoint bps startState) startState

                  let newDbg = initDebuggerAtEnd (extendBounded (past dbg) newTrace)

                  let cFinal = current newDbg
                  lastSent2 <- sendState lastSent1 False cFinal
                  logRunFinished cFinal
                  when (status cFinal == WaitingForInput) (sendResponse ResNeedInput)
                  rpcLoop exts bps lastSent2 newDbg
                else do
                  sendResponse (ResError "Emulator is not waiting for input.")
                  rpcLoop exts bps lastSent dbg
        else executeRun exts bps lastSent dbg

executeRun :: ExtensionSet -> IntSet -> Maybe CPU -> Debugger -> IO ()
executeRun exts bps lastSent dbg = do
  let c = current dbg
  if status c == Halted
    then do
      lastSent' <- sendState lastSent False c
      rpcLoop exts bps lastSent' dbg
    else do
      startState <-
        execStateT
          ( runEmulator $ do
              when (stopReason c == OnEbreak) incPC
              setStatus Running
              setStopReason NoStop
          )
          c

      lastSent1 <- sendState lastSent False startState
      newTrace <- resumeTrace Nothing bps (atBreakpoint bps startState) startState

      let newDbg = initDebuggerAtEnd (extendBounded (past dbg) newTrace)

      let cFinal = current newDbg
      lastSent2 <- sendState lastSent1 False cFinal
      logRunFinished cFinal
      when (status cFinal == WaitingForInput) (sendResponse ResNeedInput)
      rpcLoop exts bps lastSent2 newDbg

logRunFinished :: CPU -> IO ()
logRunFinished cFinal =
  when (status cFinal == Halted) $
    let n = cycles cFinal
     in sendLog Info "CPU" ("finished · executed " ++ show n ++ " instruction" ++ (if n == 1 then "" else "s"))
