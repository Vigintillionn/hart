module Main where

import Types
import Parser (parse)
import Data.Word
import Data.Vector ((!), (//))
import qualified Data.Vector as V
import qualified Data.Map as M 
import Control.Monad.State

data CPU = CPU 
    { pc    :: Word32 
    , regs  :: V.Vector Word32 
    , mem   :: M.Map Word32 Word8 
    } deriving (Show)

type Simulator a = State CPU a

-- Helper to read a register
getReg :: Register -> Simulator Word32
getReg 0 = return 0                     -- x0 is hardwired to be 0
getReg r = do
    cpuRegs <- gets regs
    return (cpuRegs ! r)

-- Helper to write to a register
setReg :: Register -> Word32 -> Simulator ()
setReg 0 _      = return ()             -- writes to x0 are ignored
setReg r val    = modify $ \cpu ->
    let newRegs = regs cpu // [(r, val)]
    in cpu { regs = newRegs }

-- Fetch a single byte, defaulting to 0 if not found
readByte :: Word32 -> Simulator Word8
readByte addr = gets (M.findWithDefault 0 addr . mem)

-- Fetch a 4-byte instruction (little endian)
fetch :: Simulator Word32 
fetch = undefined

-- Extracts bits from 'lo' to 'hi'
getBits :: Int -> Int -> Word32 -> Word32
getBits lo hi word = undefined

-- decodes a word into the correct instruction
decode :: Word32 -> Instruction
decode = undefined

execute = undefined

step :: Simulator ()
step = do
    rawInstr <- fetch                   -- fetch instruction
    let instr = decode rawInstr         -- decode
    _ <- execute instr                       -- execute
    modify (\c -> c { pc = pc c + 4 })  -- increment PC

runUntilHalt :: Simulator ()
runUntilHalt = do
    currentPC <- gets pc
    if currentPC == 0xFFFFFFFF 
        then return ()
        else do
            step
            runUntilHalt
    

main :: IO ()
main = do
    let program = "add sp, sp, ra     # this is a test\n \
    \ addi sp, sp, -0xdeadbeef"
    case parse program of
        Left inst -> print inst
        Right err -> print err



comment :: IO ()
comment = do
    let initialCPU = CPU { pc = 0, regs = V.replicate 32 0, mem = M.empty }

    let program = do
            setReg 1 20
            setReg 2 20
            modify (\c -> c { pc = 0xFFFFFFFF })

    let finalCPU = execState program initialCPU

    print (regs finalCPU ! 2)
