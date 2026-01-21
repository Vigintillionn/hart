module Decoder where
import Types 
import Data.Word (Word32)
import Data.Bits (Bits(shiftR, shiftL, (.&.), (.|.)))
import Data.Int (Int32)

opMask, rdMask, f3Mask, rs1Mask, rs2Mask, f7Mask :: (Int, Int)
opMask  = (6, 0)
rdMask  = (11, 7)
f3Mask  = (14, 12)
rs1Mask = (19, 15)
rs2Mask = (24, 20)
f7Mask  = (31, 25)

-- Extracts bits from 'lo' to 'hi'
slice :: (Int, Int) -> Word32 -> Word32
slice (hi, lo) w =
    let mask = (1 `shiftL` (hi - lo + 1)) - 1
    in (w `shiftR` lo) .&. mask

getRd, getRs1, getRs2 :: Word32 -> Int
getRd  w = fromIntegral $ slice rdMask w
getRs1 w = fromIntegral $ slice rs1Mask w
getRs2 w = fromIntegral $ slice rs2Mask w

getOpc, getF3, getF7 :: Word32 -> Word32
getOpc = slice opMask
getF3  = slice f3Mask 
getF7  = slice f7Mask

signExtend :: Int -> Word32 -> Int 
signExtend bits x =
    let shift = 32 - bits
    in fromIntegral ((fromIntegral x :: Int32) `shiftL` shift `shiftR` shift)

decodeRType :: Word32 -> Maybe (Instruction 'R Int)
decodeRType w = do
    op <- case (getF3 w, getF7 w) of
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

decodeIType :: Word32 -> Word32 -> Maybe (Instruction 'I Int)
decodeIType 0x13 w = do
    op <- case getF3 w of
        0x0 -> Just ADDI
        0x4 -> Just XORI
        0x6 -> Just ORI
        0x7 -> Just ANDI
        _   -> Nothing
    rd  <- mkRegister (getRd w)
    rs1 <- mkRegister (getRs1 w)
    let imm = signExtend 12 $ slice (31, 20) w
    return $ ArithI op (ITypeArgs rd rs1 imm)
decodeIType 0x03 w = do
    op <- case getF3 w of
        0x0 -> Just LB
        0x1 -> Just LH
        0x2 -> Just LW
        _   -> Nothing
    rd  <- mkRegister (getRd w)
    rs1 <- mkRegister (getRs1 w)
    let imm = signExtend 12 $ slice (31, 20) w
    return $ LoadI op (ITypeArgs rd rs1 imm)
decodeIType _ _ = Nothing

unpackBImm :: Word32 -> Int
unpackBImm w =
    signExtend 13 unpacked
    where
        -- B Type immediate is scrambled in the instruction
        bit12 = slice (31, 31) w    -- MSB is located at bit 31
        bit11 = slice (7, 7) w      -- bit #11 is located at bit 7
        bits10_5 = slice (30, 25) w -- bits 5-10 are located at bits 25-30
        bits4_1  = slice (11, 8) w  -- bits 1-4 are located at bits 8-11
        unpacked = (bit12 `shiftL` 12) .|.
                   (bit11 `shiftL` 11) .|.
                   (bits10_5 `shiftL` 5) .|.
                   (bits4_1 `shiftL` 1) -- bit 0 is implicitely 0 such that addresses are halfword alligned

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
    let immHi = getF7 w -- high bits of immediate are in same range as funct7
    let immLo = slice rdMask w -- low bits of immediate are in same rang as rd
    let imm = signExtend 12 $ (immHi `shiftL` 5) .|. immLo
    return $ SType op (STypeArgs rs1 rs2 imm)

decodeSome :: Word32 -> Maybe (SomeInstruction Int)
decodeSome w =
    let opcode = getOpc w 
        instr = case opcode of
            0x33    -> SomeInstruction <$> decodeRType w            -- Arithmatic
            0x13    -> SomeInstruction <$> decodeIType opcode w     -- Immediate
            0x03    -> SomeInstruction <$> decodeIType opcode w     -- Load
            0x63    -> SomeInstruction <$> decodeBType w            -- Branch
            0x23    -> SomeInstruction <$> decodeSType w            -- Store
            _       -> Nothing
    in instr

decodeWord :: Word32 -> Either String (SomeInstruction Int)
decodeWord w =
    case decodeSome w of
        Just instr  -> Right instr
        Nothing     -> Left "Invalid instruction" 

decode :: [Word32] -> Either String Program 
decode = traverse decodeWord
