module Test.Support
  ( -- * Assembling
    assemble,
    link,
    assembleFiles,
    linkFiles,
    linkRoots,

    -- * Execution
    runProgram,
    runProgramInput,
    runFiles,
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
import Data.Functor.Identity (runIdentity)
import Data.Int (Int32)
import Data.IntMap.Strict qualified as M
import Data.Vector.Unboxed qualified as V
import Data.Word (Word32)
import Error (AssemblyError (..), LinkError (..))
import Extension (defaultExtensions)
import Linker (Executable (..), resolve)
import Machine
import Parser (parse, parseWithLocs)
import Preprocess (Expanded (..), IncludeFailure (..), expandMany, locAt)
import Types

assemble :: String -> Executable
assemble src = case link src of
  Left e -> error ("link error: " ++ show e)
  Right exe -> exe

link :: String -> Either LinkError Executable
link src = case parse defaultExtensions src of
  Left e -> error ("parse error: " ++ show e)
  Right p -> resolve p

assembleFiles :: [(FilePath, String)] -> Executable
assembleFiles files = case linkFiles files of
  Left e -> error ("link error: " ++ show e)
  Right exe -> exe

-- | link several files, each a translation unit of its own
linkFiles :: [(FilePath, String)] -> Either LinkError Executable
linkFiles files = linkRoots files (map fst files)

-- | link the @roots@ as translation units, resolving @.include@ against @pool@
linkRoots :: [(FilePath, String)] -> [FilePath] -> Either LinkError Executable
linkRoots pool roots =
  case runIdentity (expandMany resolver [(n, c) | n <- roots, Just c <- [lookup n pool]]) of
    Left e -> error ("preprocess error: " ++ show e)
    Right ex -> case parseWithLocs defaultExtensions (locAt ex) (expSource ex) of
      Left e -> error ("parse error: " ++ show e)
      Right p -> resolve p
  where
    resolver _ req = pure $ case lookup req pool of
      Just content -> Right (req, content)
      Nothing -> Left NotFound

runProgram :: String -> IO CPU
runProgram = runFrom emptyCPU . assemble

runProgramInput :: String -> String -> IO CPU
runProgramInput input = runFrom emptyCPU {inputBuffer = Just input} . assemble

-- | link the @roots@ against @pool@ (as 'linkRoots') and run the result
runFiles :: [(FilePath, String)] -> [FilePath] -> IO CPU
runFiles pool roots = case linkRoots pool roots of
  Left e -> error ("link error: " ++ show e)
  Right exe -> runFrom emptyCPU exe

runFrom :: CPU -> Executable -> IO CPU
runFrom cpu0 exe = execStateT (runEmulator go) cpu0
  where
    go = do
      loadProgram exe
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
