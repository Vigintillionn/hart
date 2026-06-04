module Test.DebuggerSpec (spec) where

import CPU (loadProgram)
import Control.Monad.State.Strict (execStateT)
import Data.IntSet qualified as IntSet
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Sequence qualified as Seq
import Debugger
  ( Debugger (..),
    atBreakpoint,
    extendBounded,
    initDebuggerAtEnd,
    resumeTrace,
    rewind,
    runTrace,
    stepBack,
    stepForward,
  )
import Machine
import Test.Hspec
import Test.Support (assemble)

sampleProgram :: String
sampleProgram =
  unlines
    [ "li t0, 0", -- 0x00
      "li t1, 1", -- 0x04
      "add t0, t0, t1", -- 0x08
      "addi t1, t1, 1", -- 0x0c
      "li a7, 10", -- 0x10
      "ecall" -- 0x14
    ]

endDebugger :: IO Debugger
endDebugger = do
  trace <- runTrace Nothing (assemble sampleProgram) emptyCPU
  pure (initDebuggerAtEnd trace)

forwardToEnd :: Debugger -> Debugger
forwardToEnd d
  | Seq.null (future d) = d
  | otherwise = forwardToEnd (stepForward d)

sameState :: CPU -> CPU -> Expectation
sameState a b = (pc a, cycles a, regs a) `shouldBe` (pc b, cycles b, regs b)

spec :: Spec
spec = do
  describe "trace recording" $ do
    it "records exactly one snapshot per executed cycle (plus the seed)" $ do
      dbg <- endDebugger
      Seq.length (past dbg) `shouldBe` cycles (current dbg)

    it "halts the program at the exit ecall" $ do
      dbg <- endDebugger
      status (current dbg) `shouldBe` Halted

  describe "time travel" $ do
    it "rewind returns to the entry state" $ do
      start <- rewind <$> endDebugger
      Seq.null (past start) `shouldBe` True
      pc (current start) `shouldBe` entryPoint
      cycles (current start) `shouldBe` 0

    it "step back then step forward is the identity" $ do
      dbg <- endDebugger
      sameState (current (stepForward (stepBack dbg))) (current dbg)

    it "replaying forward from the start reproduces the final state" $ do
      dbg <- endDebugger
      let replayed = forwardToEnd (rewind dbg)
      sameState (current replayed) (current dbg)

    it "stepping back at the start is a no-op" $ do
      start <- rewind <$> endDebugger
      sameState (current (stepBack start)) (current start)

  describe "history bounding (extendBounded)" $ do
    let mk i = emptyCPU {pc = fromIntegral (i :: Int)}
    it "keeps the whole trace when under the cap" $ do
      let history = Seq.fromList [mk 1, mk 2]
          newTrace = mk 3 :| [mk 4]
      map pc (NE.toList (extendBounded history newTrace)) `shouldBe` [1, 2, 3, 4]

    it "caps at maxHistory (10000) and keeps the newest states" $ do
      let history = Seq.fromList (map mk [1 .. 10005])
          newTrace = mk 20001 :| [mk 20002, mk 20003]
          result = extendBounded history newTrace
      NE.length result `shouldBe` 10000
      pc (NE.last result) `shouldBe` 20003 -- newest survives
      pc (NE.head result) `shouldBe` 9 -- oldest 8 dropped
  describe "address breakpoints" $ do
    it "detects when the pc is in the breakpoint set" $ do
      atBreakpoint (IntSet.fromList [4, 8]) emptyCPU {pc = 8} `shouldBe` True
      atBreakpoint (IntSet.fromList [4, 8]) emptyCPU {pc = 12} `shouldBe` False

    it "resumeTrace stops on the breakpoint without executing it" $ do
      ready <-
        execStateT
          (runEmulator (loadProgram (assemble sampleProgram) >> setStatus Running))
          emptyCPU
      trace <- resumeTrace Nothing (IntSet.fromList [0x8]) False ready
      let stopped = NE.last trace
      pc stopped `shouldBe` 0x8
      status stopped `shouldBe` Paused
      stopReason stopped `shouldBe` OnAddrBreakpoint
