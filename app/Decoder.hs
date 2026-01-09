module Decoder where
import Types 
import Data.Word (Word32)
import Data.Bits (Bits(shiftR, shiftL, (.&.)))
import Data.Int (Int32)

-- Extracts bits from 'lo' to 'hi'
slice :: Int -> Int -> Word32 -> Word32
slice hi lo w =
    let mask = (1 `shiftL` (hi - lo + 1)) - 1
    in (w `shiftR` lo) .&. mask

getRd :: Word32 -> Int
getRd w = fromIntegral $ slice 11 7 w

getRs1 :: Word32 -> Int
getRs1 w = fromIntegral $ slice 19 15 w

getRs2 :: Word32 -> Int
getRs2 w = fromIntegral $ slice 24 20 w

getF3 :: Word32 -> Word32
getF3 = slice 14 12

signExtend :: Int -> Word32 -> Int 
signExtend bits x =
    let shift = 32 - bits
    in fromIntegral ((fromIntegral x :: Int32) `shiftL` shift `shiftR` shift)


decodeRType :: Word32 -> Maybe (Instruction 'R)
decodeRType w =
    let rd  = getRd w 
        rs1 = getRs1 w 
        rs2 = getRs2 w 
        f3  = getF3 w 
        f7  = slice 31 25 w
        op  = case (f3, f7) of
            (0x0, 0x0)  -> Just ADD
            (0x0, 0x20) -> Just SUB
            (0x4, 0x0)  -> Just XOR
            _           -> Nothing
    in RType <$> op <*> pure RTypeArgs 
        { r_rs2 = rs2
        , r_rs1 = rs1
        , r_rd  = rd
        } 

decodeIType :: Word32 -> Maybe (Instruction 'I)
decodeIType w = 
    let rd  = getRd w 
        rs1 = getRs1 w 
        f3  = getF3 w
        imm = signExtend 12 $ slice 31 20 w
        op  = case f3 of
            0x0 -> Just ADDI
            _   -> Nothing
    in IType <$> op <*> pure ITypeArgs 
        { i_rs1 = rs1
        , i_rd  = rd
        , i_imm = imm
        }

decodeSome :: Word32 -> Maybe SomeInstruction
decodeSome w =
    let opcode = slice 6 0 w
        instr = case opcode of
            0x33    -> SomeInstruction <$> decodeRType w
            0x13    -> SomeInstruction <$> decodeIType w
            _       -> Nothing
    in instr

decodeWord :: Word32 -> Either String SomeInstruction 
decodeWord w =
    case decodeSome w of
        Just instr  -> Right instr
        Nothing     -> Left "Invalid instruction" 

decode :: [Word32] -> Either String [SomeInstruction]
decode = traverse decodeWord
