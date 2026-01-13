module Decoder where
import Types 
import Data.Word (Word32)
import Data.Bits (Bits(shiftR, shiftL, (.&.), (.|.)))
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


decodeRType :: Word32 -> Maybe (Instruction 'R Int)
decodeRType w = do
    op <- case (getF3 w, slice 31 25 w) of
            (0x0, 0x0)  -> Just ADD
            (0x0, 0x20) -> Just SUB
            (0x4, 0x0)  -> Just XOR
            (0x6, 0x0)  -> Just OR
            (0x7, 0x0)  -> Just AND
            _           -> Nothing
    rd  <- mkRegister (getRd w)
    rs1 <- mkRegister (getRs1 w)
    rs2 <- mkRegister (getRs2 w)
    return $ RType op (RTypeArgs rd rs1 rs2)

decodeIType :: Word32 -> Maybe (Instruction 'I Int)
decodeIType w = do
    op <- case getF3 w of
        0x0 -> Just ADDI
        0x4 -> Just XORI
        0x6 -> Just ORI
        0x7 -> Just ANDI
        _   -> Nothing 

    rd  <- mkRegister (getRd w)
    rs1 <- mkRegister (getRs1 w)
    let imm = signExtend 12 $ slice 31 20 w
    return $ IType op (ITypeArgs rd rs1 imm)

unpackBImm :: Word32 -> Int
unpackBImm w =
    signExtend 13 unpacked
    where
        bit12 = slice 31 31 w
        bit11 = slice 7 7 w 
        bits10_5 = slice 30 25 w 
        bits4_1  = slice 11 8 w 
        unpacked = (bit12 `shiftL` 12) .|.
                   (bit11 `shiftL` 11) .|.
                   (bits10_5 `shiftL` 5) .|.
                   (bits4_1 `shiftL` 1) 
                   

decodeBType :: Word32 -> Maybe (Instruction 'B Int)
decodeBType w = do
    op <- case getF3 w of
        0x0 -> Just BEQ
        0x1 -> Just BNE
        _   -> Nothing
    rs1 <- mkRegister (getRs1 w)
    rs2 <- mkRegister (getRs2 w)
    let imm = unpackBImm w
    return $ BType op (BTypeArgs rs1 rs2 imm)

decodeSType :: Word32 -> Maybe (Instruction 'S Int)
decodeSType w = do
    op <- case getF3 w of
        0x0 -> Just SB
        0x1 -> Just SH
        0x2 -> Just SW
        _   -> Nothing
    rs1 <- mkRegister $ getRs1 w
    rs2 <- mkRegister $ getRs2 w
    let immHi = slice 31 25 w
    let immLo = slice 11  7 w
    let imm = signExtend 12 $ (immHi `shiftL` 5) .|. immLo
    return $ SType op (STypeArgs rs1 rs2 imm)


decodeSome :: Word32 -> Maybe (SomeInstruction Int)
decodeSome w =
    let opcode = slice 6 0 w
        instr = case opcode of
            0x33    -> SomeInstruction <$> decodeRType w
            0x13    -> SomeInstruction <$> decodeIType w
            0x63    -> SomeInstruction <$> decodeBType w
            _       -> Nothing
    in instr

decodeWord :: Word32 -> Either String (SomeInstruction Int)
decodeWord w =
    case decodeSome w of
        Just instr  -> Right instr
        Nothing     -> Left "Invalid instruction" 

decode :: [Word32] -> Either String Program 
decode = traverse decodeWord
