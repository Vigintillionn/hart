{-# LANGUAGE OverloadedStrings #-}
module RPC (runRPC) where

import Parser (parse)
import Linker (resolve)
import CPU (loadProgram, step)
import Machine (emptyCPU, Emulator(..), CPU(..), RunStatus(..))
import Control.Monad.State (runStateT, execStateT)

import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import System.IO (hFlush, stdout, isEOF)

data Command = CmdStep | CmdQuit
  deriving (Show, Eq)

instance FromJSON Command where
    parseJSON = withObject "Command" $ \v -> do
        cmd <- v .: "command"
        case cmd :: String of
            "step" -> return CmdStep
            "quit" -> return CmdQuit
            _      -> fail "Unknown command"

data Response = ResState CPU | ResError String

instance ToJSON Response where
    toJSON (ResState cpu) = object 
        [ "type" .= ("state" :: String)
        , "data" .= cpu 
        ]
    toJSON (ResError msg) = object 
        [ "type"    .= ("error" :: String)
        , "message" .= msg 
        ]

sendResponse :: Response -> IO ()
sendResponse res = do
    BL.putStrLn (encode res)
    hFlush stdout 

runRPC :: FilePath -> IO ()
runRPC filepath = do
    sourceCode <- readFile filepath
    
    case parse sourceCode of
        Left err -> sendResponse $ ResError ("Parse Error: " ++ show err)
        Right parsed -> case resolve parsed of
            Left err -> sendResponse $ ResError ("Linker Error: " ++ err)
            Right executable -> do
                readyCpu <- execStateT (runEmulator $ loadProgram executable) emptyCPU
                sendResponse (ResState readyCpu)
                rpcLoop readyCpu

rpcLoop :: CPU -> IO ()
rpcLoop cpu = do
    eof <- isEOF
    if eof then return () else do
        
        rawInput <- getLine
        case decode (BL.pack rawInput) of
            Nothing -> do
                sendResponse $ ResError "Invalid JSON command received."
                rpcLoop cpu
                
            Just CmdQuit -> 
                return () 
                
            Just CmdStep -> do
                if status cpu == Halted then do
                    sendResponse (ResState cpu)
                    rpcLoop cpu
                else do
                    (_, nextCpu) <- runStateT (runEmulator step) cpu
                    sendResponse (ResState nextCpu)
                    rpcLoop nextCpu
