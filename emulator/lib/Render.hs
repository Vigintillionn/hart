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
renderAssemblyError = go
  where
    go e = case e of
      Located ln inner -> "line " ++ show ln ++ ": " ++ go inner
      UnknownInstruction t -> "unknown instruction `" ++ t ++ "`"
      InvalidRegister t -> "invalid register `" ++ t ++ "`"
      ImmediateTooLarge v -> "immediate out of range: " ++ show v
      UnexpectedChar c -> "unexpected character " ++ show c
      EmptyParserFailed -> "could not parse input"
      ParserFail t
        | null t -> "syntax error"
        | otherwise -> "syntax error near `" ++ t ++ "`"
      EOF -> "unexpected end of input"
      ExtensionDisabled ext mnem ->
        "`" ++ mnem ++ "` requires the " ++ ext ++ " extension, which is disabled"

renderLinkError :: LinkError -> String
renderLinkError = go
  where
    go e = case e of
      LocatedLink ln inner -> "line " ++ show ln ++ ": " ++ go inner
      DuplicateLabel l -> "duplicate label `" ++ l ++ "`"
      UndefinedLabel l -> "undefined label `" ++ l ++ "`"
      ShiftOutOfRange v -> "shift amount out of range (0-31): " ++ show v
      ImmOutOfRange ctx lo hi v ->
        ctx ++ " out of range [" ++ show lo ++ ", " ++ show hi ++ "]: " ++ show v
      MisalignedTarget ctx v -> ctx ++ " target is not 2-byte aligned: " ++ show v

renderEmulatorError :: EmulatorError -> String
renderEmulatorError e = case e of
  ELocated ln inner -> "line " ++ show ln ++ ": " ++ renderEmulatorError inner
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
  EInvalidInput pc inp ->
    "Invalid integer input " ++ show inp ++ " at " ++ hex pc
  ECycleLimit lim ->
    "Cycle limit exceeded (" ++ show lim ++ " cycles); execution halted (possible infinite loop)"
  EDisabledExtension pc raw ext ->
    "Instruction at "
      ++ hex pc
      ++ " (raw: "
      ++ hex raw
      ++ ") requires the "
      ++ ext
      ++ " extension, which is disabled"

renderNotice :: Notice -> String
renderNotice n = case n of
  ProgramExitedNormally -> "Program exited normally"
  ProgramExited code raw -> "Program exited with code: " ++ show code ++ " (raw: " ++ show raw ++ ")"
  BreakpointHit -> "Breakpoint hit"

renderSystemEvent :: SystemEvent -> String
renderSystemEvent (SysFault e) = renderEmulatorError e
renderSystemEvent (SysNotice n) = renderNotice n
