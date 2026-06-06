import { describe, expect, it } from "vitest";
import {
  assemblyErrorLine,
  emulatorErrorLine,
  emulatorErrorTag,
  formatAssemblyError,
  formatEmulatorError,
  formatLinkError,
  formatNotice,
  formatSystemEvent,
  systemEventTag,
} from "./errorFormat";
import type { AssemblyError } from "../bindings/AssemblyError";
import type { LinkError } from "../bindings/LinkError";
import type { EmulatorError } from "../bindings/EmulatorError";

describe("formatAssemblyError", () => {
  it("renders concrete assembly errors", () => {
    expect(
      formatAssemblyError({ kind: "UnknownInstruction", text: " foo " }),
    ).toBe("unknown instruction `foo`");
    expect(
      formatAssemblyError({
        kind: "ExtensionDisabled",
        mnemonic: "mul",
        extension: "M",
      }),
    ).toBe("`mul` requires the M extension, which is disabled");
  });

  it("unwraps Located to its inner error", () => {
    const e: AssemblyError = {
      kind: "Located",
      line: 7,
      error: { kind: "InvalidRegister", text: "x99" },
    };
    expect(formatAssemblyError(e)).toBe("invalid register `x99`");
    expect(assemblyErrorLine(e)).toBe(7);
  });
});

describe("formatLinkError", () => {
  it("renders range and label errors", () => {
    expect(formatLinkError({ kind: "UndefinedLabel", label: "loop" })).toBe(
      "Undefined label: `loop`",
    );
    expect(
      formatLinkError({
        kind: "ImmOutOfRange",
        context: "addi immediate",
        lo: -2048,
        hi: 2047,
        value: 5000,
      }),
    ).toBe("addi immediate out of range [-2048, 2047]: 5000");
  });
});

describe("formatEmulatorError", () => {
  it("delegates to the assembly/link formatters for compile errors", () => {
    const e: EmulatorError = {
      kind: "ParseError",
      error: { kind: "EOF" },
    };
    expect(formatEmulatorError(e)).toBe("unexpected end of input");
  });

  it("formats runtime faults with hex addresses", () => {
    expect(
      formatEmulatorError({ kind: "LoadMisaligned", pc: 0x10, address: 0x201 }),
    ).toBe("Load address misaligned at 0x10 (address: 0x201)");
    expect(formatEmulatorError({ kind: "CycleLimit", limit: 10000 })).toContain(
      "Cycle limit exceeded (10000 cycles)",
    );
  });
});

describe("error line extraction", () => {
  it("reads the line through Located and nested compile errors", () => {
    expect(
      emulatorErrorLine({
        kind: "Located",
        line: 12,
        error: { kind: "IllegalInstruction", pc: 0, raw: 0 },
      }),
    ).toBe(12);

    const link: LinkError = {
      kind: "Located",
      line: 3,
      error: { kind: "DuplicateLabel", label: "main" },
    };
    expect(emulatorErrorLine({ kind: "LinkError", error: link })).toBe(3);
  });

  it("returns null when there is no line", () => {
    expect(
      emulatorErrorLine({ kind: "UnknownSyscall", pc: 0, syscall: 99 }),
    ).toBeNull();
  });
});

describe("tags", () => {
  it("derives a short tag from the error kind", () => {
    expect(
      emulatorErrorTag({ kind: "LoadMisaligned", pc: 0, address: 0 }),
    ).toBe("TRAP");
    expect(
      emulatorErrorTag({
        kind: "Located",
        line: 1,
        error: { kind: "DecodeError", pc: 0, raw: 0 },
      }),
    ).toBe("DECODE");
  });

  it("tags notices as CPU and faults by kind", () => {
    expect(
      systemEventTag({
        severity: "info",
        fault: null,
        notice: { kind: "BreakpointHit" },
      }),
    ).toBe("BREAK");
    expect(
      systemEventTag({
        severity: "error",
        fault: { kind: "OutOfMemory", address: 0 },
        notice: null,
      }),
    ).toBe("MEMORY");
  });
});

describe("notices & system events", () => {
  it("formats notices", () => {
    expect(
      formatNotice({ kind: "ProgramExited", code: 246, raw: 4294967286 }),
    ).toBe("program exited with code 246 (raw: 0xfffffff6)");
  });

  it("prefixes located faults with the source line", () => {
    expect(
      formatSystemEvent({
        severity: "error",
        notice: null,
        fault: {
          kind: "Located",
          line: 4,
          error: { kind: "IllegalInstruction", pc: 0x4, raw: 0 },
        },
      }),
    ).toMatch(/^At line 4: Illegal instruction/);
  });
});
