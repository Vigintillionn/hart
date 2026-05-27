{-# LANGUAGE OverloadedStrings #-}
module RPC (runRPC) where

import Parser (parse)
import Linker (resolve, Executable(..))
import CPU (loadProgram)
import Machine (emptyCPU, Emulator(..), CPU(..), RunStatus(..), MonadCPU (..), incPC)
import Control.Monad.State (execStateT, modify)

import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import System.IO (hFlush, stdout, isEOF)
import Debugger (Debugger (..), isAtBreakpoint, resumeTrace, stepForward, stepBack, rewind, initDebugger)
import Control.Monad (when)
import Data.Word (Word32)

data Command
    = CmdLoad String
    | CmdRun
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
            "load"         -> CmdLoad <$> v .: "data"
            "run"          -> return CmdRun
            "step_forward" -> return CmdStepFwd
            "step_back"    -> return CmdStepBack
            "rewind"       -> return CmdRewind
            "input"        -> CmdInput <$> v .: "data"
            "quit"         -> return CmdQuit
            _              -> fail "Unknown command"

data Response = ResState CPU | ResLoaded CPU [(Word32, Int)] | ResError String | ResNeedInput

instance ToJSON Response where
    toJSON (ResState cpu) = object
        [ "type" .= ("state" :: String)
        , "data" .= cpu
        ]
    toJSON (ResLoaded cpu smap) = object
        [ "type" .= ("loaded" :: String)
        , "state" .= cpu
        , "sourceMap" .= smap
        ]
    toJSON (ResError msg) = object
        [ "type"    .= ("error" :: String)
        , "message" .= msg
        ]
    toJSON ResNeedInput = object
        [ "type" .= ("need_input" :: String)
        ]

sendResponse :: Response -> IO ()
sendResponse res = do
    BL.putStrLn (encode res)
    hFlush stdout

runRPC :: FilePath -> IO ()
runRPC _ = do
    sendResponse (ResError "Backend ready. Awaiting code from Monaco...")
    let emptyDbg = Debugger [] emptyCPU []
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
                return $ Just (initDebugger [readyCpu], execSourceMap executable)

rpcLoop :: Debugger -> IO ()
rpcLoop dbg = do
    eof <- isEOF
    if eof then return () else do

        rawInput <- getLine
        case decode (BL.pack rawInput) of
            Nothing -> do
                sendResponse $ ResError "Invalid JSON command received."
                rpcLoop dbg

            Just CmdQuit -> return ()

            Just (CmdLoad sourceCode) -> do
                mNewDbg <- compileAndLoad sourceCode
                case mNewDbg of
                    Nothing -> rpcLoop dbg
                    Just (newDbg, smap) -> do
                        sendResponse (ResLoaded (current newDbg) smap)
                        rpcLoop newDbg

            Just CmdRun -> do
                let c = current dbg
                if status c == Halted then do
                    sendResponse (ResState c)
                    rpcLoop dbg
                else do
                    atBreak <- isAtBreakpoint c
                    startState <- execStateT (runEmulator $ do
                                    when atBreak incPC
                                    setStatus Running
                                  ) c

                    newTrace <- resumeTrace startState

                    let fullTrace = reverse (past dbg) ++ newTrace
                    let newDbg = case reverse fullTrace of
                            (s:ss) -> Debugger ss s []
                            []     -> dbg

                    let cFinal = current newDbg
                    if status cFinal == WaitingForInput then do
                        sendResponse (ResState cFinal)
                        sendResponse ResNeedInput
                        rpcLoop newDbg
                    else do
                        sendResponse (ResState cFinal)
                        rpcLoop newDbg

            Just CmdStepFwd -> do
                let nextDbg = stepForward dbg
                sendResponse (ResState $ current nextDbg)
                rpcLoop nextDbg

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
                if status c == WaitingForInput then do
                    startState <- execStateT (runEmulator $ do
                                    modify $ \cpu -> cpu { 
                                        inputBuffer = Just text, 
                                        status = Running,
                                        outputBuffer = outputBuffer cpu ++ text ++ "\n"
                                    }
                                  ) c

                    newTrace <- resumeTrace startState

                    let fullTrace = reverse (past dbg) ++ newTrace
                    let newDbg = case reverse fullTrace of
                            (s:ss) -> Debugger ss s []
                            []     -> dbg

                    let cFinal = current newDbg
                    if status cFinal == WaitingForInput then do
                        sendResponse (ResState cFinal)
                        sendResponse ResNeedInput
                        rpcLoop newDbg
                    else do
                        sendResponse (ResState cFinal)
                        rpcLoop newDbg
                else do
                    sendResponse (ResError "Emulator is not waiting for input.")
                    rpcLoop dbg
