module Test.ExecutionSpec (spec) where

import Test.Hspec
import Test.Support

a0, a1, a2 :: Int
a0 = 10
a1 = 11
a2 = 12

spec :: Spec
spec = do
  describe "integer arithmetic" $ do
    it "adds an immediate" $ do
      cpu <- runProgram "addi a0, zero, 5\n"
      regU cpu a0 `shouldBe` 5

    it "subtracts into a negative result" $ do
      cpu <- runProgram "li a0, 3\nli a1, 7\nsub a2, a0, a1\n"
      regS cpu a2 `shouldBe` (-4)

  describe "x0 is hardwired to zero" $ do
    it "discards writes to x0 but still reads as 0" $ do
      cpu <- runProgram "addi zero, zero, 42\nadd a0, zero, zero\n"
      regU cpu 0 `shouldBe` 0
      regU cpu a0 `shouldBe` 0

  describe "shifts" $ do
    it "SRA is arithmetic (sign-preserving)" $ do
      cpu <- runProgram "li a0, -16\nsrai a1, a0, 2\n"
      regS cpu a1 `shouldBe` (-4)

    it "SRL is logical (zero-filling)" $ do
      cpu <- runProgram "li a0, -16\nsrli a1, a0, 2\n"
      regU cpu a1 `shouldBe` 0x3FFFFFFC

    it "uses only the low 5 bits of the shift amount" $ do
      -- shift by 33 == shift by 1 (33 .&. 0x1F)
      cpu <- runProgram "li a0, 1\nli a1, 33\nsll a2, a0, a1\n"
      regU cpu a2 `shouldBe` 2

  describe "signed vs. unsigned comparison" $ do
    it "SLT treats operands as signed" $ do
      cpu <- runProgram "li a0, -1\nli a1, 1\nslt a2, a0, a1\n"
      regU cpu a2 `shouldBe` 1

    it "SLTU treats operands as unsigned" $ do
      -- -1 is 0xFFFFFFFF unsigned, which is not < 1
      cpu <- runProgram "li a0, -1\nli a1, 1\nsltu a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0

  describe "multiply (M extension)" $ do
    it "MUL keeps the low 32 bits" $ do
      cpu <- runProgram "li a0, -1\nli a1, -1\nmul a2, a0, a1\n"
      regU cpu a2 `shouldBe` 1

    it "MULH keeps the signed high 32 bits" $ do
      cpu <- runProgram "li a0, -1\nli a1, -1\nmulh a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0

    it "MULHU keeps the unsigned high 32 bits" $ do
      -- 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001
      cpu <- runProgram "li a0, -1\nli a1, -1\nmulhu a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0xFFFFFFFE

  describe "division edge cases" $ do
    it "signed division overflow (INT_MIN / -1) wraps to INT_MIN" $ do
      cpu <- runProgram "li a0, 0x80000000\nli a1, -1\ndiv a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0x80000000

    it "signed remainder of the overflow case is 0" $ do
      cpu <- runProgram "li a0, 0x80000000\nli a1, -1\nrem a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0

    it "division by zero yields all-ones" $ do
      cpu <- runProgram "li a0, 10\nli a1, 0\ndiv a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0xFFFFFFFF

    it "remainder by zero yields the dividend" $ do
      cpu <- runProgram "li a0, 10\nli a1, 0\nrem a2, a0, a1\n"
      regU cpu a2 `shouldBe` 10

  describe "upper-immediate instructions" $ do
    it "LUI places the immediate in the high 20 bits" $ do
      cpu <- runProgram "lui a0, 0x12345\n"
      regU cpu a0 `shouldBe` 0x12345000

    it "AUIPC adds the shifted immediate to the PC" $ do
      -- a0 at pc 0; a1 at pc 4 -> 4 + (1 << 12)
      cpu <- runProgram "auipc a0, 0\nauipc a1, 1\n"
      regU cpu a0 `shouldBe` 0
      regU cpu a1 `shouldBe` 0x1004

  describe "memory loads and stores" $ do
    it "round-trips a word and is little-endian" $ do
      cpu <-
        runProgram $
          unlines
            [ "li t1, 0x200",
              "li t0, 0x12345678",
              "sw t0, 0(t1)",
              "lw a0, 0(t1)", -- whole word
              "lbu a1, 0(t1)", -- least-significant byte first
              "lbu a2, 3(t1)" -- most-significant byte last
            ]
      regU cpu a0 `shouldBe` 0x12345678
      regU cpu a1 `shouldBe` 0x78
      regU cpu a2 `shouldBe` 0x12

    it "LB sign-extends while LBU zero-extends" $ do
      cpu <-
        runProgram $
          unlines
            [ "li t1, 0x200",
              "li t0, 0x80",
              "sb t0, 0(t1)",
              "lb a0, 0(t1)", -- 0x80 sign-extended
              "lbu a1, 0(t1)" -- 0x80 zero-extended
            ]
      regU cpu a0 `shouldBe` 0xFFFFFF80
      regU cpu a1 `shouldBe` 0x80

    it "LH sign-extends while LHU zero-extends" $ do
      cpu <-
        runProgram $
          unlines
            [ "li t1, 0x200",
              "li t0, 0x8001",
              "sh t0, 0(t1)",
              "lh a0, 0(t1)", -- 0x8001 sign-extended
              "lhu a1, 0(t1)" -- 0x8001 zero-extended
            ]
      regU cpu a0 `shouldBe` 0xFFFF8001
      regU cpu a1 `shouldBe` 0x8001

  describe "control flow" $ do
    it "runs a counting loop with branches and a jump" $ do
      -- sum of 1..5 == 15
      cpu <-
        runProgram $
          unlines
            [ "li a0, 0", -- accumulator
              "li t0, 1", -- i
              "li t1, 6", -- limit (exclusive)
              "loop:",
              "bge t0, t1, end",
              "add a0, a0, t0",
              "addi t0, t0, 1",
              "j loop",
              "end:"
            ]
      regU cpu a0 `shouldBe` 15
