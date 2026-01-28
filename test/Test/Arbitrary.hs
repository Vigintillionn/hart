{-# OPTIONS_GHC -Wno-orphans #-}
module Test.Arbitrary where

import Test.QuickCheck
import Types

mkReg :: Int -> Register
mkReg n = case mkRegister n of
    Just r -> r
    Nothing -> error $ "Bad Test Reg: " ++ show n

instance Arbitrary Register where
    arbitrary = do
        n <- choose (0, 31)
        return $ mkReg n

instance Arbitrary ROp where
    arbitrary = elements [ADD, SUB, XOR, OR, AND]

instance Arbitrary IArithOp where
    arbitrary = elements [ADDI, XORI, ORI, ANDI]

instance Arbitrary ILoadOp where
    arbitrary = elements [LB, LH, LW]

instance Arbitrary BOp where
    arbitrary = elements [BEQ, BNE, BLT, BGE]

instance Arbitrary SOp where
    arbitrary = elements [SB, SH, SW]

instance Arbitrary UOp where
    arbitrary = elements [AUIPC, LUI]

genImm :: Int -> Gen Int
genImm bits = choose (-(2^(bits-1)), 2^(bits-1) - 1)

instance Arbitrary (SomeInstruction Int) where
    arbitrary = oneof
        [ genRType
        , genITypeArith
        , genITypeLoad
        , genBType
        , genSType
        , genUType
        ]
      where
        genRType = do
            op <- arbitrary
            args <- RTypeArgs <$> arbitrary <*> arbitrary <*> arbitrary
            return $ SomeInstruction (RType op args)

        genITypeArith = do
            op <- arbitrary
            args <- ITypeArgs <$> arbitrary <*> arbitrary <*> genImm 12
            return $ SomeInstruction (ArithI op args)

        genITypeLoad = do
            op <- arbitrary
            args <- ITypeArgs <$> arbitrary <*> arbitrary <*> genImm 12
            return $ SomeInstruction (LoadI op args)

        genBType = do
            op <- arbitrary
            imm <- (*2) <$> genImm 12 -- Ensure alignment
            args <- BTypeArgs <$> arbitrary <*> arbitrary <*> pure imm
            return $ SomeInstruction (BType op args)

        genSType = do
            op <- arbitrary
            imm <- genImm 12
            args <- STypeArgs <$> arbitrary <*> arbitrary <*> pure imm
            return $ SomeInstruction (SType op args)

        genUType = do
            op <- arbitrary
            imm <- choose (0, 0xFFFFF) 
            args <- UTypeArgs <$> arbitrary <*> pure imm
            return $ SomeInstruction (UType op args)
