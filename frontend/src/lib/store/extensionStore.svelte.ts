import type { ExtensionInfo } from "../../bindings/ExtensionInfo";
import { sendToHaskell } from "../util";
import { loadJSON, saveJSON } from "../persist";

const STORAGE_KEY = "extensions:enabled";

class ExtensionStore {
  catalogue = $state<ExtensionInfo[]>([]);
  /** whether we've reconciled the persisted selection with the backend yet */
  private reconciled = false;

  /** ISA codes of the currently enabled extensions (e.g. `["I", "M"]`) */
  public get enabledCodes(): string[] {
    return this.catalogue.filter((e) => e.enabled).map((e) => e.code);
  }

  /**
   * The ISA naming string for the enabled set, in catalogue order
   * (e.g. `RV32IM`, or `RV32I` with M disabled). Multi-letter "Z" extensions
   * are underscore-separated per the RISC-V naming convention
   * (e.g. `RV32IM_Zicsr`). Falls back to `RV32I` until the backend has
   * announced its catalogue.
   */
  public get isaString(): string {
    const codes = this.enabledCodes;
    if (!codes.length) return "RV32I";
    let out = "RV32";
    for (const code of codes) {
      out += code.length > 1 ? "_" + code : code;
    }
    return out;
  }

  /** true once the catalogue has at least one toggleable (optional) extension */
  public get hasOptional(): boolean {
    return this.catalogue.some((e) => !e.mandatory);
  }

  /** Adopt a catalogue announced by the backend (`extensions` response) */
  public setCatalogue(list: ExtensionInfo[]) {
    if (!this.reconciled) {
      this.reconciled = true;
      const saved = loadJSON<string[] | null>(STORAGE_KEY, null);
      if (saved) {
        const adjusted = list.map((e) => ({
          ...e,
          enabled: e.mandatory || saved.includes(e.code),
        }));
        this.catalogue = adjusted;
        const codes = adjusted.filter((e) => e.enabled).map((e) => e.code);
        // only nudge the backend if our desired set differs from its default
        if (
          !sameCodes(
            codes,
            list.filter((e) => e.enabled).map((e) => e.code),
          )
        )
          sendToHaskell("set_extensions", codes);
        return;
      }
    }
    this.catalogue = list;
  }

  public toggle(code: string): boolean {
    const ext = this.catalogue.find((e) => e.code === code);
    if (!ext || ext.mandatory) return false;

    const next = this.catalogue.map((e) =>
      e.code === code ? { ...e, enabled: !e.enabled } : e,
    );
    this.catalogue = next;

    const codes = next.filter((e) => e.enabled).map((e) => e.code);
    saveJSON(STORAGE_KEY, codes);
    sendToHaskell("set_extensions", codes);
    return true;
  }
}

function sameCodes(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const set = new Set(a);
  return b.every((c) => set.has(c));
}

export const extensionStore = new ExtensionStore();
