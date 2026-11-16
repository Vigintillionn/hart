module Test.ExecutionSpec (spec) where

import Data.Word (Word32)
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

  describe "conditional zero (Zicond)" $ do
    it "CZERO.EQZ zeroes rd when the condition is zero" $ do
      cpu <- runProgram "li a0, 7\nli a1, 0\nczero.eqz a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0

    it "CZERO.EQZ copies rs1 when the condition is non-zero" $ do
      cpu <- runProgram "li a0, 7\nli a1, 3\nczero.eqz a2, a0, a1\n"
      regU cpu a2 `shouldBe` 7

    it "CZERO.NEZ zeroes rd when the condition is non-zero" $ do
      cpu <- runProgram "li a0, 7\nli a1, 3\nczero.nez a2, a0, a1\n"
      regU cpu a2 `shouldBe` 0

    it "CZERO.NEZ copies rs1 when the condition is zero" $ do
      cpu <- runProgram "li a0, 7\nli a1, 0\nczero.nez a2, a0, a1\n"
      regU cpu a2 `shouldBe` 7

    it "the pair selects between two values without branching" $ do
      -- a2 = (a2 != 0) ? a0 : a1
      cpu <-
        runProgram
          "li a0, 11\nli a1, 22\nli a2, 1\nczero.eqz t0, a0, a2\nczero.nez t1, a1, a2\nor a2, t0, t1\n"
      regU cpu a2 `shouldBe` 11

  describe "address generation (Zba)" $ do
    binaryCase "sh1add" "3" "100" 106
    binaryCase "sh2add" "3" "100" 112
    binaryCase "sh3add" "3" "100" 124

  describe "basic bit manipulation (Zbb)" $ do
    binaryCase "andn" "0xFF" "0x0F" 0xF0
    binaryCase "orn" "0xF0" "0x0F" 0xFFFFFFF0
    binaryCase "xnor" "0xFF" "0x0F" 0xFFFFFF0F
    binaryCase "max" "-1" "1" 1
    binaryCase "maxu" "-1" "1" 0xFFFFFFFF
    binaryCase "min" "-1" "1" 0xFFFFFFFF
    binaryCase "minu" "-1" "1" 1
    binaryCase "rol" "0x80000001" "1" 0x00000003
    binaryCase "ror" "0x80000001" "1" 0xC0000000
    -- only the low 5 bits of the rotate amount count
    binaryCase "rol" "0x80000001" "33" 0x00000003
    immediateCase "rori" "1" "4" 0x10000000
    unaryCase "clz" "1" 31
    unaryCase "clz" "0" 32
    unaryCase "clz" "-1" 0
    unaryCase "ctz" "8" 3
    unaryCase "ctz" "0" 32
    unaryCase "cpop" "0xF0F0" 8
    unaryCase "sext.b" "0x80" 0xFFFFFF80
    unaryCase "sext.b" "0x17F" 0x7F
    unaryCase "sext.h" "0x8000" 0xFFFF8000
    unaryCase "zext.h" "0x12345678" 0x5678
    unaryCase "orc.b" "0x00120034" 0x00FF00FF
    unaryCase "rev8" "0x12345678" 0x78563412

  describe "single-bit operations (Zbs)" $ do
    binaryCase "bclr" "0xFF" "0" 0xFE
    binaryCase "bset" "0" "31" 0x80000000
    binaryCase "binv" "0xFF" "4" 0xEF
    binaryCase "bext" "0x10" "4" 1
    -- only the low 5 bits of the bit index count
    binaryCase "bset" "0" "33" 2
    immediateCase "bclri" "0xFF" "7" 0x7F
    immediateCase "bseti" "0" "5" 0x20
    immediateCase "binvi" "0" "0" 1
    immediateCase "bexti" "0x10" "3" 0
    immediateCase "bexti" "0x10" "4" 1

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

binaryCase :: String -> String -> String -> Word32 -> Spec
binaryCase mnemonic lhs rhs expected =
  it (unwords [mnemonic, lhs ++ ",", rhs]) $ do
    cpu <- runProgram (unlines ["li a0, " ++ lhs, "li a1, " ++ rhs, mnemonic ++ " a2, a0, a1"])
    regU cpu a2 `shouldBe` expected

immediateCase :: String -> String -> String -> Word32 -> Spec
immediateCase mnemonic lhs imm expected =
  it (unwords [mnemonic, lhs ++ ",", imm]) $ do
    cpu <- runProgram (unlines ["li a0, " ++ lhs, mnemonic ++ " a2, a0, " ++ imm])
    regU cpu a2 `shouldBe` expected

unaryCase :: String -> String -> Word32 -> Spec
unaryCase mnemonic input expected =
  it (unwords [mnemonic, input]) $ do
    cpu <- runProgram (unlines ["li a0, " ++ input, mnemonic ++ " a2, a0"])
    regU cpu a2 `shouldBe` expected
