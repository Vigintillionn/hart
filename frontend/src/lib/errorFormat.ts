import type { AssemblyError } from "../bindings/AssemblyError";
import type { LinkError } from "../bindings/LinkError";
import type { EmulatorError } from "../bindings/EmulatorError";
import type { Notice } from "../bindings/Notice";
import type { SystemEvent } from "../bindings/SystemEvent";

const hex = (w: number) => "0x" + (w >>> 0).toString(16);

export function formatAssemblyError(e: AssemblyError): string {
  switch (e.kind) {
    case "Located":
      return formatAssemblyError(e.error);
    case "UnknownInstruction":
      return `unknown instruction \`${e.text.trim()}\``;
    case "InvalidRegister":
      return `invalid register \`${e.text.trim()}\``;
    case "ImmediateTooLarge":
      return `immediate out of range: ${e.value}`;
    case "UnexpectedChar":
      return `unexpected character '${e.char}'`;
    case "EmptyParserFailed":
      return "could not parse input";
    case "ParserFail":
      return e.text ? `syntax error near \`${e.text.trim()}\`` : "syntax error";
    case "EOF":
      return "unexpected end of input";
    case "ExtensionDisabled":
      return `\`${e.mnemonic.trim()}\` requires the ${e.extension} extension, which is disabled`;
    case "CsrOutOfRange":
      return `${e.context} out of range [${e.lo}, ${e.hi}]: ${e.value}`;
  }
}

export function formatLinkError(e: LinkError): string {
  switch (e.kind) {
    case "Located":
      return formatLinkError(e.error);
    case "DuplicateLabel":
      return `Duplicate label: \`${e.label.trim()}\``;
    case "UndefinedLabel":
      return `Undefined label: \`${e.label.trim()}\``;
    case "ShiftOutOfRange":
      return `Shift amount out of range (0-31): ${e.value}`;
    case "ImmOutOfRange":
      return `${e.context} out of range [${e.lo}, ${e.hi}]: ${e.value}`;
    case "MisalignedTarget":
      return `${e.context} target is not 2-byte aligned: ${e.value}`;
  }
}

export function formatEmulatorError(e: EmulatorError): string {
  switch (e.kind) {
    case "Located":
      return formatEmulatorError(e.error);
    case "ParseError":
      return formatAssemblyError(e.error);
    case "LinkError":
      return formatLinkError(e.error);
    case "DecodeError":
      return `Invalid instruction at ${hex(e.pc)} (raw: ${hex(e.raw)})`;
    case "IllegalInstruction":
      return `Illegal instruction at ${hex(e.pc)} (raw: ${hex(e.raw)}). Did the program run past its code without calling exit, or jump into uninitialized memory?`;
    case "InstrMisaligned":
      return `Instruction address misaligned at ${hex(e.pc)} (target: ${hex(e.target)})`;
    case "LoadMisaligned":
      return `Load address misaligned at ${hex(e.pc)} (address: ${hex(e.address)})`;
    case "StoreMisaligned":
      return `Store address misaligned at ${hex(e.pc)} (address: ${hex(e.address)})`;
    case "UnknownSyscall":
      return `Unknown syscall ${e.syscall} at ${hex(e.pc)}`;
    case "OutOfMemory":
      return `Out of memory: sbrk to ${hex(e.address)} collided with the stack`;
    case "InvalidInput":
      return `Invalid integer input \`${e.input.trim()}\` at ${hex(e.pc)}`;
    case "CycleLimit":
      return `Cycle limit exceeded (${e.limit} cycles); execution halted (possible infinite loop)`;
    case "DisabledExtension":
      return `Instruction at ${hex(e.pc)} (raw: ${hex(e.raw)}) requires the ${e.extension} extension, which is disabled`;
  }
}

export function formatNotice(n: Notice): string {
  switch (n.kind) {
    case "ProgramExitedNormally":
      return "program exited with code 0";
    case "ProgramExited":
      return `program exited with code ${n.code} (raw: ${hex(n.raw)})`;
    case "BreakpointHit":
      return "breakpoint hit";
    case "Syscall": {
      const times = n.count > 1 ? ` ×${n.count}` : "";
      const bytes = n.bytes !== null ? ` (${n.bytes}B)` : "";
      return `${n.name} @${hex(n.pc)}${times}${bytes}`;
    }
  }
}

export function formatSystemEvent(ev: SystemEvent): string {
  if (ev.fault) {
    const line = emulatorErrorLine(ev.fault);
    const msg = formatEmulatorError(ev.fault);
    return line !== null ? `At line ${line}: ${msg}` : msg;
  }
  if (ev.notice) return formatNotice(ev.notice);
  return "";
}

/** Short system-log tag derived from an emulator error's kind. */
export function emulatorErrorTag(e: EmulatorError): string {
  switch (e.kind) {
    case "Located":
      return emulatorErrorTag(e.error);
    case "ParseError":
      return "PARSE";
    case "LinkError":
      return "LINK";
    case "DecodeError":
      return "DECODE";
    case "IllegalInstruction":
      return "ILLEGAL";
    case "InstrMisaligned":
    case "LoadMisaligned":
    case "StoreMisaligned":
      return "TRAP";
    case "UnknownSyscall":
      return "SYSCALL";
    case "OutOfMemory":
      return "MEMORY";
    case "InvalidInput":
      return "INPUT";
    case "CycleLimit":
      return "CYCLES";
    case "DisabledExtension":
      return "EXT";
  }
}

export function noticeTag(n: Notice): string {
  switch (n.kind) {
    case "Syscall":
      return "ECALL";
    case "ProgramExitedNormally":
    case "ProgramExited":
      return "EXIT";
    case "BreakpointHit":
      return "BREAK";
  }
}

/** Tag for a system-log entry derived from the event (fault kind, or notice). */
export function systemEventTag(ev: SystemEvent): string {
  if (ev.fault) return emulatorErrorTag(ev.fault);
  if (ev.notice) return noticeTag(ev.notice);
  return "CPU";
}

/** The source line an assembly error points at, if any (via `Located`). */
export function assemblyErrorLine(e: AssemblyError): number | null {
  return e.kind === "Located" ? e.line : null;
}

/** The source line a link error points at, if any (via `Located`). */
export function linkErrorLine(e: LinkError): number | null {
  return e.kind === "Located" ? e.line : null;
}

/**
 * The source line an emulator error points at, if any. Runtime faults are
 * wrapped in `Located` by the backend (via the pc→line map); compile errors
 * carry the line inside their `ParseError`/`LinkError` payload.
 */
export function emulatorErrorLine(e: EmulatorError): number | null {
  if (e.kind === "Located") return e.line;
  if (e.kind === "ParseError") return assemblyErrorLine(e.error);
  if (e.kind === "LinkError") return linkErrorLine(e.error);
  return null;
}
