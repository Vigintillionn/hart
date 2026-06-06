import type * as Monaco from "monaco-editor";
import { isaStore } from "$lib/store/isaStore.svelte";
import type { InstructionInfo } from "../../bindings/InstructionInfo";
import type { PseudoInfo } from "../../bindings/PseudoInfo";
import type { DirectiveInfo } from "../../bindings/DirectiveInfo";
import { REGISTERS, type RegisterInfo } from "$lib/store/helpCatalogue.svelte";
import { editorPrefs } from "$lib/store/editorPrefs.svelte";

const dot = " · ";

function instrMarkdown(i: InstructionInfo): string {
  const fmt = isaStore.format(i.format);
  const head = [
    `**${i.mnemonic}**`,
    fmt?.name,
    fmt?.syntax ? "`" + fmt.syntax + "`" : null,
  ]
    .filter(Boolean)
    .join(dot);
  return [head, "`" + i.operation + "`", i.description]
    .filter(Boolean)
    .join("\n\n");
}

function pseudoMarkdown(p: PseudoInfo): string {
  const head = [
    `**${p.mnemonic}**`,
    "_pseudo_",
    p.syntax ? "`" + p.syntax + "`" : null,
  ]
    .filter(Boolean)
    .join(dot);
  const expands = p.expands ? `Expands to \`${p.expands}\`` : null;
  return [head, expands, p.description].filter(Boolean).join("\n\n");
}

function directiveMarkdown(d: DirectiveInfo): string {
  const head = [`**${d.name}**`, d.args ? "`" + d.args + "`" : null]
    .filter(Boolean)
    .join(dot);
  return [head, d.description].filter(Boolean).join("\n\n");
}

function registerMarkdown(r: RegisterInfo): string {
  const head = [`**${r.abi}**`, r.arch, r.saver ? `saver: ${r.saver}` : null]
    .filter(Boolean)
    .join(dot);
  return [head, r.desc].filter(Boolean).join("\n\n");
}

// Every register by both its ABI name(s) (e.g. s0, fp) and its x-name (x8).
const registerByName = new Map<string, RegisterInfo>();
for (const r of REGISTERS) {
  registerByName.set(r.arch.toLowerCase(), r);
  for (const name of r.abi.split("/"))
    registerByName.set(name.toLowerCase(), r);
}

/**
 * Markdown doc for a token, honouring the per-category hover toggles. Prefers a
 * real instruction over a pseudo; categories are otherwise disjoint.
 */
function lookup(token: string): string | null {
  if (editorPrefs.hoverInstructions) {
    const i = isaStore.instructions.find((x) => x.mnemonic === token);
    if (i) return instrMarkdown(i);
    const p = isaStore.pseudos.find((x) => x.mnemonic === token);
    if (p) return pseudoMarkdown(p);
  }
  if (editorPrefs.hoverDirectives) {
    const d = isaStore.directives.find((x) => x.name === `.${token}`);
    if (d) return directiveMarkdown(d);
  }
  if (editorPrefs.hoverRegisters) {
    const r = registerByName.get(token);
    if (r) return registerMarkdown(r);
  }
  return null;
}

const HOVER_KEY = Symbol.for("hart.riscvHoverProvider");

export function registerRiscvHover(monaco: typeof Monaco): void {
  const g = globalThis as Record<symbol, Monaco.IDisposable | undefined>;
  g[HOVER_KEY]?.dispose();
  g[HOVER_KEY] = monaco.languages.registerHoverProvider("riscv", {
    provideHover(model, position) {
      const word = model.getWordAtPosition(position);
      if (!word) return null;
      const md = lookup(word.word.toLowerCase());
      if (!md) return null;
      return {
        range: new monaco.Range(
          position.lineNumber,
          word.startColumn,
          position.lineNumber,
          word.endColumn,
        ),
        contents: [{ value: md }],
      };
    },
  });
}
