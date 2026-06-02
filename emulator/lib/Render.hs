module Render
  ( renderAssemblyError,
    renderLinkError,
    renderEmulatorError,
    renderNotice,
    renderSystemEvent,
  )
where

import Data.Word (Word32)
import Error
import Numeric (showHex)

hex :: Word32 -> String
hex w = "0x" ++ showHex w ""

renderAssemblyError :: AssemblyError -> String
renderAssemblyError e = case e of
  UnknownInstruction t -> "Unknown instruction: " ++ t
  InvalidRegister t -> "Invalid register: " ++ t
  ImmediateTooLarge v -> "Immediate too large: " ++ show v
  UnexpectedChar c -> "Unexpected character: " ++ show c
  EmptyParserFailed -> "Parser failed"
  ParserFail t -> t
  EOF -> "Unexpected end of input"

renderLinkError :: LinkError -> String
renderLinkError e = case e of
  DuplicateLabel l -> "Duplicate label: " ++ l
  UndefinedLabel l -> "Undefined label: " ++ l
  ShiftOutOfRange v -> "Shift amount out of range (0-31): " ++ show v
  ImmOutOfRange ctx lo hi v ->
    ctx ++ " out of range [" ++ show lo ++ ", " ++ show hi ++ "]: " ++ show v
  MisalignedTarget ctx v -> ctx ++ " target is not 2-byte aligned: " ++ show v

renderEmulatorError :: EmulatorError -> String
renderEmulatorError e = case e of
  EParse a -> "Parse error: " ++ renderAssemblyError a
  ELink l -> "Link error: " ++ renderLinkError l
  EDecode pc raw -> "Invalid instruction at " ++ hex pc ++ " (raw: " ++ hex raw ++ ")"
  EIllegalInstruction pc raw ->
    "Illegal instruction at "
      ++ hex pc
      ++ " (raw: "
      ++ hex raw
      ++ "). "
      ++ "Did the program run past its code without calling exit, or jump into uninitialized memory?"
  EInstrMisaligned pc tgt ->
    "Instruction address misaligned at " ++ hex pc ++ " (target: " ++ hex tgt ++ ")"
  ELoadMisaligned pc addr ->
    "Load address misaligned at " ++ hex pc ++ " (address: " ++ hex addr ++ ")"
  EStoreMisaligned pc addr ->
    "Store address misaligned at " ++ hex pc ++ " (address: " ++ hex addr ++ ")"
  EUnknownSyscall pc a7 -> "Unknown syscall " ++ show a7 ++ " at " ++ hex pc
  EOutOfMemory addr ->
    "Out of memory: sbrk to " ++ hex addr ++ " collided with the stack"

renderNotice :: Notice -> String
renderNotice n = case n of
  ProgramExitedNormally -> "Program exited normally"
  ProgramExited code -> "Program exited with code: " ++ show code
  BreakpointHit -> "Breakpoint hit"

renderSystemEvent :: SystemEvent -> String
renderSystemEvent (SysFault e) = renderEmulatorError e
renderSystemEvent (SysNotice n) = renderNotice n
