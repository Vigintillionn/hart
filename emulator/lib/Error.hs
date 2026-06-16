{-# LANGUAGE OverloadedStrings #-}

module Error
  ( -- * Phase-specific errors
    AssemblyError (..),
    LinkError (..),

    -- * Unified error
    EmulatorError (..),

    -- * Runtime system channel
    Severity (..),
    Notice (..),
    SystemEvent (..),
    eventSeverity,
    recordNotice,
  )
where

import Data.Aeson (ToJSON (..), Value, object, (.=))
import Data.Word (Word32)
import Loc (Loc (..))

-- | Parse-time failures produced by "Parser".
data AssemblyError
  = UnknownInstruction String
  | InvalidRegister String
  | ImmediateTooLarge Int
  | UnexpectedChar Char
  | EmptyParserFailed
  | ParserFail String
  | EOF
  | -- | a mnemonic that belongs to a disabled extension: its ISA code and the
    -- offending mnemonic
    ExtensionDisabled String String
  | -- | a CSR operand outside its valid range: context, lower bound, upper
    -- bound, offending value
    CsrOutOfRange String Int Int Int
  | -- | source location + the underlying failure that occurred there
    Located Loc AssemblyError
  deriving (Show, Eq)

-- | Link-time failures produced by "Linker" (symbol resolution + range checks).
data LinkError
  = DuplicateLabel String
  | UndefinedLabel String
  | ShiftOutOfRange Int
  | -- | context, lower bound, upper bound, offending value
    ImmOutOfRange String Int Int Int
  | -- | context, offending value
    MisalignedTarget String Int
  | -- | division or modulo by zero in an expression
    DivByZero
  | -- | a constant (@.equ@/@.set@/@.equiv@) whose value refers back to itself,
    -- directly or transitively: the offending symbol name
    CircularConstant String
  | -- | source location + the underlying failure that occurred there
    LocatedLink Loc LinkError
  deriving (Show, Eq)

data EmulatorError
  = EParse AssemblyError
  | ELink LinkError
  | -- | pc, raw instruction word
    EDecode Word32 Word32
  | -- | pc, raw instruction word
    EIllegalInstruction Word32 Word32
  | -- | pc, jump/branch target
    EInstrMisaligned Word32 Word32
  | -- | pc, address
    ELoadMisaligned Word32 Word32
  | -- | pc, address
    EStoreMisaligned Word32 Word32
  | -- | pc, a7 (syscall number)
    EUnknownSyscall Word32 Word32
  | -- | requested break address
    EOutOfMemory Word32
  | -- | pc, the offending input that could not be parsed
    EInvalidInput Word32 String
  | -- | the cycle ceiling that was exceeded (execution was force-halted)
    ECycleLimit Int
  | -- | pc, raw instruction word, ISA code of the disabled extension it needs
    EDisabledExtension Word32 Word32 String
  | -- | source line + the underlying runtime fault that occurred there
    ELocated Int EmulatorError
  deriving (Show, Eq)

data Severity = Info | Warning | SevError
  deriving (Show, Eq)

-- | An informational, non-error event on the system channel.
data Notice
  = -- | `ecall` exit (syscall 10)
    ProgramExitedNormally
  | -- | `ecall` exit with code (syscall 93): the POSIX exit status (low 8
    -- bits of a0) and the raw a0 register value
    ProgramExited Word32 Word32
  | -- | `ebreak`
    BreakpointHit
  | -- | one or more `ecall`s were dispatched: the syscall's friendly name, the
    -- pc it was issued from, an optional payload size in bytes (summed across
    -- repeats, for I/O syscalls), and how many consecutive identical calls were
    -- folded into this entry (1 for a single call)
    SyscallCalled String Word32 (Maybe Int) Int
  deriving (Show, Eq)

data SystemEvent
  = SysFault EmulatorError
  | SysNotice Notice
  deriving (Show, Eq)

recordNotice :: Notice -> [SystemEvent] -> [SystemEvent]
recordNotice n@(SyscallCalled nm p by cnt) evs =
  case break (sameSite nm p) evs of
    (before, SysNotice (SyscallCalled _ _ by' cnt') : after) ->
      before ++ SysNotice (SyscallCalled nm p (addBytes by' by) (cnt' + cnt)) : after
    _ -> SysNotice n : evs
  where
    sameSite a b (SysNotice (SyscallCalled a' b' _ _)) = a == a' && b == b'
    sameSite _ _ _ = False
recordNotice n evs = SysNotice n : evs

addBytes :: Maybe Int -> Maybe Int -> Maybe Int
addBytes (Just a) (Just b) = Just (a + b)
addBytes Nothing b = b
addBytes a Nothing = a

eventSeverity :: SystemEvent -> Severity
eventSeverity (SysNotice _) = Info
eventSeverity (SysFault e) = faultSeverity e
  where
    -- look through the 'ELocated' wrapper so a fault keeps its severity once a
    -- source line is attached
    faultSeverity (ELocated _ inner) = faultSeverity inner
    faultSeverity (EUnknownSyscall _ _) = Warning
    faultSeverity (EOutOfMemory _) = Warning
    faultSeverity _ = SevError

instance ToJSON Severity where
  toJSON Info = "info"
  toJSON Warning = "warning"
  toJSON SevError = "error"

kind :: String -> Value
kind k = object ["kind" .= k]

instance ToJSON AssemblyError where
  toJSON e = case e of
    UnknownInstruction t -> object ["kind" .= s "UnknownInstruction", "text" .= t]
    InvalidRegister t -> object ["kind" .= s "InvalidRegister", "text" .= t]
    ImmediateTooLarge v -> object ["kind" .= s "ImmediateTooLarge", "value" .= v]
    UnexpectedChar c -> object ["kind" .= s "UnexpectedChar", "char" .= [c]]
    EmptyParserFailed -> kind "EmptyParserFailed"
    ParserFail t -> object ["kind" .= s "ParserFail", "text" .= t]
    EOF -> kind "EOF"
    ExtensionDisabled ext mnem ->
      object ["kind" .= s "ExtensionDisabled", "extension" .= ext, "mnemonic" .= mnem]
    CsrOutOfRange ctx lo hi v ->
      object ["kind" .= s "CsrOutOfRange", "context" .= ctx, "lo" .= lo, "hi" .= hi, "value" .= v]
    Located loc inner ->
      object ["kind" .= s "Located", "line" .= locLine loc, "file" .= locFile loc, "error" .= inner]

instance ToJSON LinkError where
  toJSON e = case e of
    DuplicateLabel l -> object ["kind" .= s "DuplicateLabel", "label" .= l]
    UndefinedLabel l -> object ["kind" .= s "UndefinedLabel", "label" .= l]
    ShiftOutOfRange v -> object ["kind" .= s "ShiftOutOfRange", "value" .= v]
    ImmOutOfRange ctx lo hi v ->
      object ["kind" .= s "ImmOutOfRange", "context" .= ctx, "lo" .= lo, "hi" .= hi, "value" .= v]
    MisalignedTarget ctx v ->
      object ["kind" .= s "MisalignedTarget", "context" .= ctx, "value" .= v]
    DivByZero -> kind "DivByZero"
    CircularConstant n -> object ["kind" .= s "CircularConstant", "name" .= n]
    LocatedLink loc inner ->
      object ["kind" .= s "Located", "line" .= locLine loc, "file" .= locFile loc, "error" .= inner]

instance ToJSON EmulatorError where
  toJSON e = case e of
    EParse a -> object ["kind" .= s "ParseError", "error" .= a]
    ELink l -> object ["kind" .= s "LinkError", "error" .= l]
    EDecode pc raw -> object ["kind" .= s "DecodeError", "pc" .= pc, "raw" .= raw]
    EIllegalInstruction pc raw -> object ["kind" .= s "IllegalInstruction", "pc" .= pc, "raw" .= raw]
    EInstrMisaligned pc tgt -> object ["kind" .= s "InstrMisaligned", "pc" .= pc, "target" .= tgt]
    ELoadMisaligned pc addr -> object ["kind" .= s "LoadMisaligned", "pc" .= pc, "address" .= addr]
    EStoreMisaligned pc addr -> object ["kind" .= s "StoreMisaligned", "pc" .= pc, "address" .= addr]
    EUnknownSyscall pc a7 -> object ["kind" .= s "UnknownSyscall", "pc" .= pc, "syscall" .= a7]
    EOutOfMemory addr -> object ["kind" .= s "OutOfMemory", "address" .= addr]
    EInvalidInput pc inp -> object ["kind" .= s "InvalidInput", "pc" .= pc, "input" .= inp]
    ECycleLimit lim -> object ["kind" .= s "CycleLimit", "limit" .= lim]
    EDisabledExtension pc raw ext ->
      object ["kind" .= s "DisabledExtension", "pc" .= pc, "raw" .= raw, "extension" .= ext]
    ELocated ln inner -> object ["kind" .= s "Located", "line" .= ln, "error" .= inner]

instance ToJSON Notice where
  toJSON n = case n of
    ProgramExitedNormally -> kind "ProgramExitedNormally"
    ProgramExited code raw -> object ["kind" .= s "ProgramExited", "code" .= code, "raw" .= raw]
    BreakpointHit -> kind "BreakpointHit"
    SyscallCalled name p bytes cnt ->
      object ["kind" .= s "Syscall", "name" .= name, "pc" .= p, "bytes" .= bytes, "count" .= cnt]

instance ToJSON SystemEvent where
  toJSON ev = object (("severity" .= eventSeverity ev) : body)
    where
      body = case ev of
        SysFault e -> ["fault" .= e]
        SysNotice n -> ["notice" .= n]

s :: String -> String
s = id
