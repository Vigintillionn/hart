import type { FormatInfo } from "../../bindings/FormatInfo";
import type { InstructionInfo } from "../../bindings/InstructionInfo";
import type { PseudoInfo } from "../../bindings/PseudoInfo";
import type { SyscallInfo } from "../../bindings/SyscallInfo";
import { extensionStore } from "./extensionStore.svelte";
import { helpStore } from "./helpStore.svelte";
import { isaStore } from "./isaStore.svelte";

const FALLBACK_NAMES: Record<string, string> = {
  I: "Base Integer",
  M: "Multiply / Divide",
};

export type ExtGroup = { code: string; name: string; enabled: boolean };
export type FmtGroup = { fmt: FormatInfo; items: InstructionInfo[] };
export type ExtSection = ExtGroup & { fmtGroups: FmtGroup[] };
export type AsciiInfo = {
  dec: number;
  hex: string;
  char: string;
  desc: string;
  isControl: boolean;
};
export type RegisterInfo = {
  abi: string;
  arch: string;
  saver: "Caller" | "Callee" | "N/A";
  desc: string;
};

const ASCII_TABLE: AsciiInfo[] = Array.from({ length: 128 }, (_, i) => {
  const hex = i.toString(16).padStart(2, "0").toUpperCase();
  let char = String.fromCharCode(i);
  let desc = "";

  const controlMap: Record<number, { c: string; d: string }> = {
    0: { c: "NUL", d: "Null" },
    1: { c: "SOH", d: "Start of Heading" },
    2: { c: "STX", d: "Start of Text" },
    3: { c: "ETX", d: "End of Text" },
    4: { c: "EOT", d: "End of Trans." },
    5: { c: "ENQ", d: "Enquiry" },
    6: { c: "ACK", d: "Acknowledge" },
    7: { c: "BEL", d: "Bell" },
    8: { c: "BS", d: "Backspace" },
    9: { c: "TAB", d: "Horizontal Tab" },
    10: { c: "LF", d: "Line Feed" },
    11: { c: "VT", d: "Vertical Tab" },
    12: { c: "FF", d: "Form Feed" },
    13: { c: "CR", d: "Carriage Return" },
    14: { c: "SO", d: "Shift Out" },
    15: { c: "SI", d: "Shift In" },
    16: { c: "DLE", d: "Data Link Esc." },
    17: { c: "DC1", d: "Device Ctrl 1" },
    18: { c: "DC2", d: "Device Ctrl 2" },
    19: { c: "DC3", d: "Device Ctrl 3" },
    20: { c: "DC4", d: "Device Ctrl 4" },
    21: { c: "NAK", d: "Negative Ack." },
    22: { c: "SYN", d: "Sync. Idle" },
    23: { c: "ETB", d: "End Trans. Blk" },
    24: { c: "CAN", d: "Cancel" },
    25: { c: "EM", d: "End of Medium" },
    26: { c: "SUB", d: "Substitute" },
    27: { c: "ESC", d: "Escape" },
    28: { c: "FS", d: "File Separator" },
    29: { c: "GS", d: "Group Separator" },
    30: { c: "RS", d: "Record Separator" },
    31: { c: "US", d: "Unit Separator" },
    32: { c: "SPC", d: "Space" },
    127: { c: "DEL", d: "Delete" },
  };

  const isControl = !!controlMap[i];
  if (isControl) {
    char = controlMap[i].c;
    desc = controlMap[i].d;
  }
  return { dec: i, hex, char, desc, isControl };
});

const REGISTER_TABLE: RegisterInfo[] = [
  { abi: "zero", arch: "x0", saver: "N/A", desc: "Hard-wired zero" },
  { abi: "ra", arch: "x1", saver: "Caller", desc: "Return address" },
  {
    abi: "sp",
    arch: "x2",
    saver: "Callee",
    desc: "Stack pointer; points to current top of the stack.",
  },
  {
    abi: "gp",
    arch: "x3",
    saver: "N/A",
    desc: "Global pointer; provides access to global variables.",
  },
  {
    abi: "tp",
    arch: "x4",
    saver: "N/A",
    desc: "Thread pointer; provides access to thread-local storage variables.",
  },
  { abi: "t0…t2", arch: "x5…x7", saver: "Caller", desc: "Temporary registers" },
  {
    abi: "s0/fp",
    arch: "x8",
    saver: "Callee",
    desc: "Saved register / frame pointer; points to the base of the current stack frame.",
  },
  { abi: "s1", arch: "x9", saver: "Callee", desc: "Saved register" },
  {
    abi: "a0…a1",
    arch: "x10…x11",
    saver: "Caller",
    desc: "Function arguments / return values",
  },
  {
    abi: "a2…a7",
    arch: "x12…x17",
    saver: "Caller",
    desc: "Function arguments",
  },
  { abi: "s2…s11", arch: "x18…x27", saver: "Callee", desc: "Saved registers" },
  {
    abi: "t3…t6",
    arch: "x27…x31",
    saver: "Caller",
    desc: "Temporary registers",
  },
];

class HelpCatalogue {
  private get query() {
    return helpStore.q;
  }

  private match(text: string) {
    return !this.query || text.toLowerCase().includes(this.query);
  }

  /** Every extension that has a catalogue entry or contributes an instruction */
  readonly extGroups = $derived.by<ExtGroup[]>(() => {
    const codes: string[] = [];
    for (const e of extensionStore.catalogue)
      if (!codes.includes(e.code)) codes.push(e.code);
    for (const i of isaStore.instructions)
      if (!codes.includes(i.extension)) codes.push(i.extension);
    return codes.map((code) => {
      const cat = extensionStore.catalogue.find((e) => e.code === code);
      return {
        code,
        name: cat?.name ?? FALLBACK_NAMES[code] ?? `${code} extension`,
        enabled: cat ? cat.enabled : true,
      };
    });
  });

  /** Extension sections matching the query, grouped by instruction forma. */
  readonly extSections = $derived.by<ExtSection[]>(() => {
    const codes =
      helpStore.group === "all"
        ? this.extGroups.map((g) => g.code)
        : helpStore.group === "pseudo" || helpStore.group === "syscall"
          ? []
          : [helpStore.group];

    return codes
      .map((code) => {
        const instrs = isaStore.instructions.filter(
          (i) => i.extension === code && this.instrMatches(i),
        );
        // group by format, in the order the backend lists them
        const fmtGroups = isaStore.formats
          .map((fmt) => ({
            fmt,
            items: instrs.filter((i) => i.format === fmt.id),
          }))
          .filter((g) => g.items.length > 0);
        const g = this.extGroups.find((e) => e.code === code);
        return {
          code,
          name: g?.name ?? code,
          enabled: g?.enabled ?? true,
          fmtGroups,
        };
      })
      .filter((s) => s.fmtGroups.length > 0);
  });

  private instrMatches(i: InstructionInfo) {
    const f = isaStore.format(i.format);
    return this.match(
      `${i.mnemonic} ${i.operation} ${i.description} ${f?.name ?? ""} ${f?.kind ?? ""}`,
    );
  }

  /** Pseudo-instructions matching the query */
  readonly visiblePseudos = $derived<PseudoInfo[]>(
    helpStore.group === "all" || helpStore.group === "pseudo"
      ? isaStore.pseudos.filter((p) =>
          this.match(`${p.mnemonic} ${p.syntax} ${p.description} ${p.expands}`),
        )
      : [],
  );

  /** Syscalls matching the query */
  readonly visibleSyscalls = $derived<SyscallInfo[]>(
    helpStore.group === "all" || helpStore.group === "syscall"
      ? isaStore.syscalls.filter((s) =>
          this.match(
            `${s.name} ${s.code} ${s.registers.map((r) => `${r.reg} ${r.desc}`).join(" ")} ${s.description}`,
          ),
        )
      : [],
  );

  readonly visibleAscii = $derived<AsciiInfo[]>(
    helpStore.group === "all" || helpStore.group === "ascii"
      ? ASCII_TABLE.filter((a) =>
          this.match(`ascii ${a.char} ${a.dec} 0x${a.hex} ${a.desc}`),
        )
      : [],
  );

  readonly visibleRegisters = $derived<RegisterInfo[]>(
    helpStore.group === "all" || helpStore.group === "registers"
      ? REGISTER_TABLE.filter((r) =>
          this.match(`${r.abi} ${r.arch} ${r.saver} ${r.desc}`),
        )
      : [],
  );

  readonly isEmpty = $derived(
    this.extSections.length === 0 &&
      this.visiblePseudos.length === 0 &&
      this.visibleSyscalls.length === 0 &&
      this.visibleAscii.length === 0 &&
      this.visibleRegisters.length === 0,
  );
}

export const helpCatalogue = new HelpCatalogue();
