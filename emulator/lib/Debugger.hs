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
import Machine (CPU (..), Emulator (..), MonadCPU (..), Register (unReg), RunStatus (..), getCSR, incPC, trapBreakpointM)
import Numeric (readHex)
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

loop :: IntSet -> Bool -> Seq CPU -> CPU -> IO (Seq CPU)
loop bps skipFirst acc curr
  | not skipFirst && status curr == Running && atBreakpoint bps curr =
      return (markLastPaused acc)
  | otherwise = do
      (running, next) <- runStateT (runEmulator step) curr

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
                else newAcc `seq` loop bps False newAcc next
            else newAcc `seq` loop bps False newAcc next
        else return newAcc

atBreakpoint :: IntSet -> CPU -> Bool
atBreakpoint bps c = IntSet.member (fromIntegral (pc c)) bps

markLastPaused :: Seq CPU -> Seq CPU
markLastPaused (rest :|> c) = rest |> c {status = Paused}
markLastPaused Empty = Empty

resumeTrace :: IntSet -> Bool -> CPU -> IO (Seq CPU)
resumeTrace bps skipFirst currentCpu =
  loop bps skipFirst (Seq.singleton currentCpu) currentCpu

runTrace :: Executable -> CPU -> IO (Seq CPU)
runTrace prog startCPU = do
  cpuReady <- execStateT (runEmulator $ loadProgram prog) startCPU
  loop IntSet.empty False (Seq.singleton cpuReady) cpuReady

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
   in printf "0x%08x:  %-48s  |%s|" startAddr hexPart ascPart

isAtBreakpoint :: CPU -> IO Bool
isAtBreakpoint = evalStateT (runEmulator check)
  where
    check :: (MonadCPU m) => m Bool
    check = do
      cause <- getCSR 0x342 -- mcause
      epc <- getCSR 0x341 -- mepc
      currentPC <- getPC
      return (cause == trapBreakpointM && epc == currentPC)

isHalted :: CPU -> IO Bool
isHalted c = do
  w <- evalStateT (runEmulator fetch) c
  return (w == 0)

runInteractive :: Debugger -> IO ()
runInteractive dbg = do
  putStrLn "\n----------------------------------------"

  let c = current dbg
  w <- evalStateT (runEmulator fetch) c

  let instrStr =
        if w == 0
          then "NOP / HALTED"
          else case decodeWord w of
            Left err -> "<Decode Error: " ++ err ++ ">"
            Right inst -> disassemble inst

  printf "PC: 0x%08x | Cycle: %d | %s\n" (pc c) (cycles c) instrStr

  print (viewRegisters $ regs c)
  putStrLn "CSRs:"
  putStrLn (viewCSRs $ csrs c)

  putStrLn "[p]rev, [n]ext, [c]ontinue, [r]ewind, [m]emory <address>, [q]uit: "
  cmd <- getLine
  let tokens = words cmd

  case tokens of
    ["p"] -> runInteractive (stepBack dbg)
    ["n"] -> case future dbg of
      Empty -> case status c of
        Halted -> do
          putStrLn ">> Execution Finished. Cannot step."
          runInteractive dbg
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

          runInteractive newDbg
      _ -> runInteractive (stepForward dbg)
    ["r"] -> runInteractive (rewind dbg)
    ["q"] -> putStrLn "Exiting debugger."
    ["c"] -> do
      case status c of
        Halted -> do
          putStrLn ">> Execution Finished (Halted)."
          runInteractive dbg
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
          newTrace <- resumeTrace IntSet.empty False startState

          let fullTrace = past dbg <> newTrace
          let newDbg = initDebuggerAtEnd fullTrace

          runInteractive newDbg
    ["m", addrStr] -> do
      let parsedAddr =
            if take 2 addrStr == "0x"
              then readHex (drop 2 addrStr)
              else readHex addrStr
      case parsedAddr of
        [(addr, "")] -> do
          putStrLn $ viewMemory c addr 16
          runInteractive dbg
        _ -> do
          putStrLn "Invalid address format. Use: m 0x2000"
          runInteractive dbg
    [] -> runInteractive dbg
    _ -> runInteractive dbg

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
