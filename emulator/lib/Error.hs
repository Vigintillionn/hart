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
  )
where

import Data.Aeson (ToJSON (..), Value, object, (.=))
import Data.Word (Word32)

-- | Parse-time failures produced by "Parser".
data AssemblyError
  = UnknownInstruction String
  | InvalidRegister String
  | ImmediateTooLarge Int
  | UnexpectedChar Char
  | EmptyParserFailed
  | ParserFail String
  | EOF
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
  deriving (Show, Eq)

data Severity = Info | Warning | SevError
  deriving (Show, Eq)

-- | An informational, non-error event on the system channel.
data Notice
  = -- | `ecall` exit (syscall 10)
    ProgramExitedNormally
  | -- | `ecall` exit with code (syscall 93)
    ProgramExited Word32
  | -- | `ebreak`
    BreakpointHit
  deriving (Show, Eq)

data SystemEvent
  = SysFault EmulatorError
  | SysNotice Notice
  deriving (Show, Eq)

eventSeverity :: SystemEvent -> Severity
eventSeverity (SysNotice _) = Info
eventSeverity (SysFault e) = case e of
  EUnknownSyscall _ _ -> Warning
  EOutOfMemory _ -> Warning
  _ -> SevError

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

instance ToJSON LinkError where
  toJSON e = case e of
    DuplicateLabel l -> object ["kind" .= s "DuplicateLabel", "label" .= l]
    UndefinedLabel l -> object ["kind" .= s "UndefinedLabel", "label" .= l]
    ShiftOutOfRange v -> object ["kind" .= s "ShiftOutOfRange", "value" .= v]
    ImmOutOfRange ctx lo hi v ->
      object ["kind" .= s "ImmOutOfRange", "context" .= ctx, "lo" .= lo, "hi" .= hi, "value" .= v]
    MisalignedTarget ctx v ->
      object ["kind" .= s "MisalignedTarget", "context" .= ctx, "value" .= v]

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

instance ToJSON Notice where
  toJSON n = case n of
    ProgramExitedNormally -> kind "ProgramExitedNormally"
    ProgramExited code -> object ["kind" .= s "ProgramExited", "code" .= code]
    BreakpointHit -> kind "BreakpointHit"

instance ToJSON SystemEvent where
  toJSON ev = object (("severity" .= eventSeverity ev) : body)
    where
      body = case ev of
        SysFault e -> ["fault" .= e]
        SysNotice n -> ["notice" .= n]

s :: String -> String
s = id
