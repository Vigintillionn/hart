module Test.Support
  ( -- * Assembling
    assemble,
    link,

    -- * Execution
    runProgram,
    runProgramInput,
    regU,
    regS,
    csr,
    output,

    -- * Inspection
    reg,
    realInstrOf,
    directiveOf,

    -- * Error unwrapping
    underlyingLink,
    underlyingParse,
  )
where

import CPU (loadProgram, step)
import Control.Monad (when)
import Control.Monad.State.Strict (execStateT)
import Data.Int (Int32)
import Data.IntMap.Strict qualified as M
import Data.Vector.Unboxed qualified as V
import Data.Word (Word32)
import Error (AssemblyError (..), LinkError (..))
import Extension (defaultExtensions)
import Linker (Executable (..), resolve)
import Machine
import Parser (parse)
import Types

assemble :: String -> Executable
assemble src = case link src of
  Left e -> error ("link error: " ++ show e)
  Right exe -> exe

link :: String -> Either LinkError Executable
link src = case parse defaultExtensions src of
  Left e -> error ("parse error: " ++ show e)
  Right p -> resolve p

runProgram :: String -> IO CPU
runProgram = runFrom emptyCPU

runProgramInput :: String -> String -> IO CPU
runProgramInput input = runFrom emptyCPU {inputBuffer = Just input}

runFrom :: CPU -> String -> IO CPU
runFrom cpu0 src = execStateT (runEmulator go) cpu0
  where
    go = do
      loadProgram (assemble src)
      setStatus Running
      loop (100000 :: Int)
    loop 0 = pure ()
    loop n = do
      continue <- step
      when continue $ loop (n - 1)

regU :: CPU -> Int -> Word32
regU cpu i = regs cpu V.! i

regS :: CPU -> Int -> Int32
regS cpu i = fromIntegral (regU cpu i)

-- | Read a CSR by address, defaulting to 0 when it was never written.
csr :: CPU -> Int -> Word32
csr cpu addr = M.findWithDefault 0 addr (csrs cpu)

-- | The program's accumulated console output.
output :: CPU -> String
output = renderOutput . outputBuffer

reg :: Int -> Register
reg n = case mkRegister n of
  Just r -> r
  Nothing -> error ("bad register index: " ++ show n)

realInstrOf :: String -> SomeInstruction Operand
realInstrOf src = case parse defaultExtensions src of
  Right [(_, (_, Just (StmtInstr (RealInstr si))))] -> si
  Right _ -> error "expected exactly one real instruction"
  Left e -> error ("parse error: " ++ show e)

directiveOf :: String -> Directive
directiveOf src = case parse defaultExtensions src of
  Right [(_, (_, Just (StmtDirective d)))] -> d
  Right _ -> error "expected exactly one directive"
  Left e -> error ("parse error: " ++ show e)

underlyingLink :: LinkError -> LinkError
underlyingLink (LocatedLink _ e) = underlyingLink e
underlyingLink e = e

underlyingParse :: AssemblyError -> AssemblyError
underlyingParse (Located _ e) = underlyingParse e
underlyingParse e = e
