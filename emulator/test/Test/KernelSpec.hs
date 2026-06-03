module Test.KernelSpec (spec) where

import Machine (RunStatus (..), heapTop, status)
import Test.Hspec
import Test.Support

a0 :: Int
a0 = 10

spec :: Spec
spec = do
  describe "console output syscalls" $ do
    it "print_int (1) writes the signed decimal value" $ do
      cpu <- runProgram "li a0, -5\nli a7, 1\necall\n"
      output cpu `shouldBe` "-5"

    it "print_char (11) writes a single character" $ do
      cpu <- runProgram "li a0, 65\nli a7, 11\necall\n"
      output cpu `shouldBe` "A"

    it "print_string (4) writes a NUL-terminated string from memory" $ do
      -- exercises .data layout + the `la` pseudo + readCString together
      cpu <-
        runProgram $
          unlines
            [ ".data",
              "msg: .string \"hi\"",
              ".text",
              "la a0, msg",
              "li a7, 4",
              "ecall"
            ]
      output cpu `shouldBe` "hi"

  describe "input syscalls" $ do
    it "read_int (5) parses a decimal from the input buffer" $ do
      cpu <- runProgramInput "123" "li a7, 5\necall\n"
      regS cpu a0 `shouldBe` 123

  describe "process exit" $ do
    it "exit (10) halts and prints the normal-exit message" $ do
      cpu <- runProgram "li a7, 10\necall\n"
      status cpu `shouldBe` Halted
      output cpu `shouldBe` "Program exited normally\n"

    it "exit2 (93) reports the low 8 bits of the exit code" $ do
      cpu <- runProgram "li a0, 42\nli a7, 93\necall\n"
      status cpu `shouldBe` Halted
      output cpu `shouldBe` "Program exited with code: 42\n"

  describe "sbrk (214)" $ do
    it "returns the current break when asked for 0" $ do
      cpu <- runProgram "li a0, 0\nli a7, 214\necall\n"
      regU cpu a0 `shouldBe` 0x20000000 -- heapBase
    it "grows the break and returns the new value" $ do
      cpu <- runProgram "li a0, 0x20001000\nli a7, 214\necall\n"
      regU cpu a0 `shouldBe` 0x20001000
      heapTop cpu `shouldBe` 0x20001000
