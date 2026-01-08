{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
module Assembler where
import Types 
import Data.Word
import Data.Bits (Bits(shiftL, (.|.)))

getRFmt :: ROp -> (Word32, Word32, Word32)
getRFmt op = (opc, f3, f7)
    where
        opc = 0x67
        f3  = case op of
            XOR -> 0x4
            _   -> 0x0
        f7  = case op of
            SUB -> 0x20
            _   -> 0x0

assembleRType :: Instruction 'R -> Word32
assembleRType (RType op args) =
    opc .|.
    (rd `shiftL` 7) .|.
    (f3 `shiftL` 12) .|.
    (rs1 `shiftL` 15) .|.
    (rs2 `shiftL` 20) .|.
    (f7 `shiftL` 25)
    where
       (opc, f3, f7) = getRFmt op 
       rd   = fromIntegral $ r_rd args
       rs1  = fromIntegral $ r_rs1 args
       rs2  = fromIntegral $ r_rs2 args 

assembleIType :: Instruction 'I -> Word32
assembleIType = undefined

assembleSome :: SomeInstruction -> Word32
assembleSome (SomeInstruction instr@(RType _ _)) = assembleRType instr
assembleSome (SomeInstruction instr@(IType _ _)) = assembleIType instr
