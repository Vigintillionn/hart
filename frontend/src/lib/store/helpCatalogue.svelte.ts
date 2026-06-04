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

  readonly isEmpty = $derived(
    this.extSections.length === 0 &&
      this.visiblePseudos.length === 0 &&
      this.visibleSyscalls.length === 0,
  );
}

export const helpCatalogue = new HelpCatalogue();
