module Debugger where

import CPU
import Control.Monad (when)
import Control.Monad.State.Strict
import Data.Char (chr, isPrint, toLower)
import Data.Int (Int32)
import Data.IntMap.Strict qualified as M
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Data.Sequence (Seq (..), (<|), (|>))
import Data.Sequence qualified as Seq
import Data.Vector.Unboxed qualified as V
import Data.Word (Word32)
import Decoder (decodeWord)
import Linker (Executable)
import Machine (CPU (..), Emulator (..), MonadCPU (..), Register (unReg), RunStatus (..), incPC)
import Numeric (readHex)
import Render (renderEmulatorError, renderSystemEvent)
import System.IO (hReady, stdin)
import Text.Printf (printf)
import Types

data Debugger = Debugger
  { past :: Seq CPU,
    current :: CPU,
    future :: Seq CPU
  }

maxHistory :: Int
maxHistory = 10000

initDebugger :: Seq CPU -> Debugger
initDebugger Empty = error "Trace cannot be empty"
initDebugger (c :<| cs) =
  Debugger
    { past = Empty,
      current = c,
      future = cs
    }

initDebuggerAtEnd :: Seq CPU -> Debugger
initDebuggerAtEnd t0 =
  case boundHistory t0 of
    Empty -> error "Trace cannot be empty"
    ss :|> s ->
      Debugger
        { past = ss,
          current = s,
          future = Empty
        }

boundHistory :: Seq CPU -> Seq CPU
boundHistory t
  | extra > 0 = Seq.drop extra t
  | otherwise = t
  where
    extra = Seq.length t - maxHistory

pauseIfRunning :: CPU -> CPU
pauseIfRunning s
  | status s == Running = s {status = Paused}
  | otherwise = s

stepForward :: Debugger -> Debugger
stepForward dbg@(Debugger p c f) = case f of
  Empty -> dbg
  f' :<| fs -> Debugger (p |> c) (pauseIfRunning f') fs

stepBack :: Debugger -> Debugger
stepBack dbg@(Debugger p c f) = case p of
  Empty -> dbg
  ps :|> p' -> Debugger ps (p' {status = Paused}) (c <| f)

rewind :: Debugger -> Debugger
rewind dbg = case past dbg of
  Empty -> dbg
  _ -> rewind (stepBack dbg)

-- | Run to completion, recording every intermediate state. @mLimit@ is an
-- optional cycle ceiling: when the executed cycle count reaches it the run is
-- force-halted with an 'ECycleLimit' fault, so an infinite-loop program can't
-- spin forever. 'Nothing' means unbounded.
loop :: Maybe Int -> IntSet -> Bool -> Seq CPU -> CPU -> IO (Seq CPU)
loop mLimit bps skipFirst acc curr
  | not skipFirst && status curr == Running && atBreakpoint bps curr =
      return (markLastPaused acc)
  | otherwise = do
      (stepRunning, stepped) <- runStateT (runEmulator step) curr

      (running, next) <- case mLimit of
        Just lim | stepRunning && cycles stepped >= lim -> do
          halted <- execStateT (runEmulator (haltCycleLimit lim)) stepped
          return (False, halted)
        _ -> return (stepRunning, stepped)

      let newAcc =
            if Seq.length acc >= maxHistory
              then Seq.drop 1 acc |> next
              else acc |> next

      if running
        then do
          if cycles next `mod` 10000 == 0
            then do
              ready <- hReady stdin
              if ready
                then return (newAcc `seq` newAcc)
                else newAcc `seq` loop mLimit bps False newAcc next
            else newAcc `seq` loop mLimit bps False newAcc next
        else return newAcc

atBreakpoint :: IntSet -> CPU -> Bool
atBreakpoint bps c = IntSet.member (fromIntegral (pc c)) bps

markLastPaused :: Seq CPU -> Seq CPU
markLastPaused (rest :|> c) = rest |> c {status = Paused}
markLastPaused Empty = Empty

resumeTrace :: Maybe Int -> IntSet -> Bool -> CPU -> IO (Seq CPU)
resumeTrace mLimit bps skipFirst currentCpu =
  loop mLimit bps skipFirst (Seq.singleton currentCpu) currentCpu

runTrace :: Maybe Int -> Executable -> CPU -> IO (Seq CPU)
runTrace mLimit prog startCPU = do
  cpuReady <- execStateT (runEmulator $ loadProgram prog >> setStatus Running) startCPU
  loop mLimit IntSet.empty False (Seq.singleton cpuReady) cpuReady

viewRegisters :: V.Vector Word32 -> [Int32]
viewRegisters regs = map fromIntegral (V.toList regs)

viewCSRs :: M.IntMap Word32 -> String
viewCSRs csrMap =
  let validCSRs = filter (\(k, _) -> k >= 0x300) (M.toList csrMap)
   in unlines $ map fmt validCSRs
  where
    fmt (addr, val) = printf "  %s: 0x%08x" (decodeCSRName addr) val

viewMemory :: CPU -> Int -> Int -> String
viewMemory c startAddr len =
  let bytes = map (\a -> M.findWithDefault 0 a (mem c)) [startAddr .. startAddr + len - 1]
      hexPart = unwords $ map (printf "%02x") bytes
      ascPart = map (\b -> let ch = chr (fromIntegral b) in if isPrint ch then ch else '.') bytes
      hexWidth = max 0 (len * 3 - 1)
   in printf "0x%08x:  %-*s  |%s|" startAddr hexWidth hexPart ascPart

isAtBreakpoint :: CPU -> IO Bool
isAtBreakpoint c = do
  w <- evalStateT (runEmulator fetch) c
  return $ case decodeWord w of
    Right (SomeInstruction (Trap EBREAK)) -> True
    _ -> False

isHalted :: CPU -> IO Bool
isHalted c = do
  w <- evalStateT (runEmulator fetch) c
  return (w == 0)

-- | Interactive trace debugger REPL. @mLimit@ is the optional cycle ceiling
-- applied to the @[c]@ontinue command (so resuming a looping program can't
-- hang the CLI); see 'loop'.
runInteractive :: Maybe Int -> Debugger -> IO ()
runInteractive mLimit = go
  where
    go dbg = do
      putStrLn "\n----------------------------------------"

      let c = current dbg
      w <- evalStateT (runEmulator fetch) c

      let instrStr =
            if w == 0
              then "NOP / HALTED"
              else case decodeWord w of
                Left err -> "<" ++ renderEmulatorError err ++ ">"
                Right inst -> disassemble inst

      printf "PC: 0x%08x | Cycle: %d | %s\n" (pc c) (cycles c) instrStr

      print (viewRegisters $ regs c)
      putStrLn "CSRs:"
      putStrLn (viewCSRs $ csrs c)

      case reverse (systemLog c) of
        [] -> return ()
        evts -> do
          putStrLn "System log:"
          mapM_ (\e -> putStrLn ("  " ++ renderSystemEvent e)) evts

      putStrLn "[p]rev, [n]ext, [c]ontinue, [r]ewind, [m]emory <address>, [q]uit: "
      cmd <- getLine
      let tokens = words cmd

      case tokens of
        ["p"] -> go (stepBack dbg)
        ["n"] -> case future dbg of
          Empty -> case status c of
            Halted -> do
              putStrLn ">> Execution Finished. Cannot step."
              go dbg
            _ -> do
              atBreak <- isAtBreakpoint c
              startState <-
                execStateT
                  ( runEmulator $ do
                      when atBreak incPC
                      setStatus Running
                  )
                  c
              (_, nextState) <- runStateT (runEmulator step) startState

              let newDbg =
                    Debugger
                      { past = past dbg |> c,
                        current = nextState,
                        future = Empty
                      }

              go newDbg
          _ -> go (stepForward dbg)
        ["r"] -> go (rewind dbg)
        ["q"] -> putStrLn "Exiting debugger."
        ["c"] -> do
          case status c of
            Halted -> do
              putStrLn ">> Execution Finished (Halted)."
              go dbg
            _ -> do
              atBreak <- isAtBreakpoint c
              if atBreak
                then putStrLn ">> Resuming from breakpoint..."
                else putStrLn ">> Resuming..."
              startState <-
                execStateT
                  ( runEmulator $ do
                      when atBreak incPC
                      setStatus Running
                  )
                  c
              newTrace <- resumeTrace mLimit IntSet.empty False startState

              let fullTrace = past dbg <> newTrace
              let newDbg = initDebuggerAtEnd fullTrace

              go newDbg
        ["m", addrStr] -> do
          let parsedAddr =
                if take 2 addrStr == "0x"
                  then readHex (drop 2 addrStr)
                  else readHex addrStr
          case parsedAddr of
            [(addr, "")] -> do
              putStrLn $ viewMemory c addr 16
              go dbg
            _ -> do
              putStrLn "Invalid address format. Use: m 0x2000"
              go dbg
        [] -> go dbg
        _ -> go dbg

formatReg :: Register -> String
formatReg r = "x" ++ show (unReg r)

disassemble :: SomeInstruction Int -> String
disassemble (SomeInstruction i) = case i of
  RType op args ->
    printf "%s %s, %s, %s" (low op) (f $ r_rd args) (f $ r_rs1 args) (f $ r_rs2 args)
  ArithI op args ->
    printf "%s %s, %s, %d" (low op) (f $ i_rd args) (f $ i_rs1 args) (i_imm args)
  LoadI op args ->
    printf "%s %s, %d(%s)" (low op) (f $ i_rd args) (i_imm args) (f $ i_rs1 args)
  JumpI op args ->
    printf "%s %s, %s, %d" (low op) (f $ i_rd args) (f $ i_rs1 args) (i_imm args)
  BType op args ->
    printf "%s %s, %s, %d" (low op) (f $ b_rs1 args) (f $ b_rs2 args) (b_imm args)
  SType op args ->
    printf "%s %s, %d(%s)" (low op) (f $ s_rs2 args) (s_imm args) (f $ s_rs1 args)
  UType op args ->
    printf "%s %s, 0x%x" (low op) (f $ u_rd args) (u_imm args)
  JType op args ->
    printf "%s %s, %d" (low op) (f $ j_rd args) (j_imm args)
  System op args ->
    printf "%s %s, %s, %s" (low op) (f $ c_rd args) (decodeCSRName $ c_csr args) (f $ c_rs1 args)
  SystemI op args ->
    printf "%s %s, %s, %d" (low op) (f $ ci_rd args) (decodeCSRName $ ci_csr args) (ci_uimm args)
  Trap op -> low op
  where
    low :: (Show a) => a -> String
    low = map toLower . show
    f = formatReg
