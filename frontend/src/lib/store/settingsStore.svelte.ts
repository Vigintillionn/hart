import type { IconName } from "../types";
import { extensionStore } from "./extensionStore.svelte";
import { editorPrefs } from "./editorPrefs.svelte";
import { displayStore } from "./displayStore.svelte";
import { terminalStore } from "./terminalStore.svelte";
import { modeStore } from "./mode.svelte";
import { resetThemes } from "../editor/theme.svelte";
import { keymap, COMMANDS } from "../keymap.svelte";

/** The categories shown in the settings window sidebar. */
export type CategoryId =
  | "appearance"
  | "editor"
  | "display"
  | "terminal"
  | "shortcuts"
  | "extensions"
  | "about";

export interface CategoryMeta {
  id: CategoryId;
  label: string;
  icon: IconName;
  section: string;
}

export const SETTINGS_SECTIONS = ["Interface", "Machine", "Other"];

export interface SettingDescriptor {
  id: string;
  category: CategoryId;
  title: string;
  description?: string;
  keywords?: string[];
}

export const SETTINGS_CATEGORIES: CategoryMeta[] = [
  { id: "appearance", label: "Appearance", icon: "sun", section: "Interface" },
  { id: "editor", label: "Editor", icon: "pencil", section: "Interface" },
  { id: "terminal", label: "Terminal", icon: "term", section: "Interface" },
  {
    id: "shortcuts",
    label: "Keyboard",
    icon: "keyboard",
    section: "Interface",
  },
  { id: "display", label: "Registers & Memory", icon: "memory", section: "Machine" }, // prettier-ignore
  {
    id: "extensions",
    label: "ISA Extensions",
    icon: "chip",
    section: "Machine",
  },
  { id: "about", label: "About", icon: "info", section: "Other" },
];

export const SETTINGS: SettingDescriptor[] = [
  {
    id: "appearance.mode",
    category: "appearance",
    title: "Theme",
    description: "Follow your system, or force a light or dark appearance.",
    keywords: [
      "dark",
      "light",
      "system",
      "auto",
      "mode",
      "color scheme",
      "appearance",
    ],
  },
  {
    id: "editor.fontFamily",
    category: "editor",
    title: "Font family",
    description: "Monospace typeface used in the code editor.",
    keywords: ["font", "typeface", "family", "monospace", "jetbrains"],
  },
  {
    id: "editor.fontSize",
    category: "editor",
    title: "Font size",
    description: "Editor text size in pixels.",
    keywords: ["font", "size", "zoom", "text"],
  },
  {
    id: "editor.tabWidth",
    category: "editor",
    title: "Tab width",
    description: "Number of columns a tab occupies.",
    keywords: ["tab", "width", "indent", "size"],
  },
  {
    id: "editor.indentStyle",
    category: "editor",
    title: "Indent with",
    description: "Insert spaces or a tab character when indenting.",
    keywords: ["spaces", "tabs", "indent", "indentation"],
  },
  {
    id: "editor.lineNumbers",
    category: "editor",
    title: "Line numbers",
    description: "Absolute, relative, or hidden line numbers.",
    keywords: ["line", "numbers", "gutter", "relative", "absolute"],
  },
  {
    id: "editor.wordWrap",
    category: "editor",
    title: "Word wrap",
    description: "Wrap long lines instead of scrolling horizontally.",
    keywords: ["word", "wrap", "soft", "lines"],
  },
  {
    id: "editor.whitespace",
    category: "editor",
    title: "Show whitespace",
    description: "Render whitespace dots and control characters.",
    keywords: ["whitespace", "spaces", "control", "characters", "invisibles"],
  },
  {
    id: "editor.minimap",
    category: "editor",
    title: "Minimap",
    description: "Show the code overview on the right edge.",
    keywords: ["minimap", "overview", "preview"],
  },
  {
    id: "editor.hover",
    category: "editor",
    title: "Hover documentation",
    description: "Show reference docs when hovering code in the editor.",
    keywords: ["hover", "tooltip", "docs", "documentation", "reference", "all"],
  },
  {
    id: "editor.hoverInstructions",
    category: "editor",
    title: "Instruction hover",
    description: "Show docs for instructions and pseudo-instructions.",
    keywords: ["hover", "instruction", "pseudo", "opcode", "mnemonic", "docs"],
  },
  {
    id: "editor.hoverDirectives",
    category: "editor",
    title: "Directive hover",
    description: "Show docs for assembler directives such as .word.",
    keywords: ["hover", "directive", "assembler", "docs"],
  },
  {
    id: "editor.hoverRegisters",
    category: "editor",
    title: "Register hover",
    description: "Show the ABI role and saver of registers such as sp, a0.",
    keywords: ["hover", "register", "abi", "saver", "calling", "convention"],
  },
  {
    id: "display.registerNaming",
    category: "display",
    title: "Register names",
    description: "Show ABI names (ra, sp) or numeric names (x1, x2) first.",
    keywords: ["register", "abi", "numeric", "names", "alias", "x0"],
  },
  {
    id: "display.signedMode",
    category: "display",
    title: "Signed mode",
    description:
      "Display register values as signed or unsigned integers when viewing them as decimal values.",
    keywords: ["signed", "unsigned", "integer", "values", "display"],
  },
  {
    id: "display.endianness",
    category: "display",
    title: "Memory byte order",
    description:
      "Byte order within each cell; only applies when grouping above 1 byte.",
    keywords: ["endian", "endianness", "little", "big", "byte", "order"],
  },
  {
    id: "display.byteWidth",
    category: "display",
    title: "Bytes per group",
    description: "How many bytes each memory cell combines.",
    keywords: ["byte", "width", "group", "word", "halfword", "memory"],
  },
  {
    id: "display.followMemoryWrites",
    category: "display",
    title: "Follow memory writes",
    description:
      "Automatically scroll to memory locations when they are written to.",
    keywords: ["follow", "memory", "writes", "scroll", "auto-scroll"],
  },
  {
    id: "display.flashChanges",
    category: "display",
    title: "Highlight changes",
    description:
      "Briefly flash registers and memory that changed after a step.",
    keywords: ["highlight", "flash", "changed", "diff", "step"],
  },
  {
    id: "terminal.clearOnRun",
    category: "terminal",
    title: "Clear program console on run",
    description: "Wipe the program output each time you start a run.",
    keywords: ["clear", "console", "program", "output", "run", "terminal"],
  },
  {
    id: "terminal.autoSwitch",
    category: "terminal",
    title: "Auto-switch console tabs",
    description:
      "Focus the relevant console on compile, error, or input requests.",
    keywords: ["auto", "switch", "tab", "console", "focus", "terminal"],
  },
  {
    id: "editor.background",
    category: "editor",
    title: "Editor background",
    description: "Background colour of the code canvas.",
    keywords: ["canvas", "background", "syntax", "color"],
  },
  {
    id: "editor.keyword",
    category: "editor",
    title: "Instructions",
    description: "Mnemonics such as li, add, jal.",
    keywords: ["keyword", "instruction", "mnemonic", "syntax", "color"],
  },
  {
    id: "editor.register",
    category: "editor",
    title: "Registers",
    description: "Register operands such as x0, a0, sp.",
    keywords: ["register", "operand", "syntax", "color"],
  },
  {
    id: "editor.directive",
    category: "editor",
    title: "Directives",
    description: "Assembler directives such as .text, .data.",
    keywords: ["directive", "section", "syntax", "color"],
  },
  {
    id: "editor.number",
    category: "editor",
    title: "Numbers",
    description: "Integer and hexadecimal literals.",
    keywords: ["number", "integer", "hex", "literal", "syntax", "color"],
  },
  {
    id: "editor.string",
    category: "editor",
    title: "Strings",
    description: "Quoted string literals.",
    keywords: ["string", "literal", "syntax", "color"],
  },
  {
    id: "editor.comment",
    category: "editor",
    title: "Comments",
    description: "Line comments starting with #.",
    keywords: ["comment", "syntax", "color"],
  },
];

class SettingsStore {
  open = $state(false);
  active = $state<CategoryId>("appearance");
  query = $state("");

  public get q(): string {
    return this.query.trim().toLowerCase();
  }

  public descriptor(id: string): SettingDescriptor | undefined {
    return SETTINGS.find((s) => s.id === id);
  }

  private haystack(d: SettingDescriptor): string {
    const cat =
      SETTINGS_CATEGORIES.find((c) => c.id === d.category)?.label ?? "";
    return [d.title, d.description ?? "", cat, ...(d.keywords ?? [])]
      .join(" ")
      .toLowerCase();
  }

  public matchesId(id: string): boolean {
    if (!this.q) return true;
    const d = this.descriptor(id);
    if (!d) return true;
    return this.haystack(d).includes(this.q);
  }

  public categoryHasMatches(id: CategoryId): boolean {
    const q = this.q;
    if (!q) return true;

    const cat = SETTINGS_CATEGORIES.find((c) => c.id === id);
    if (cat?.label.toLowerCase().includes(q)) return true;

    if (SETTINGS.some((s) => s.category === id && this.haystack(s).includes(q)))
      return true;

    // ISA extensions are populated at runtime from the backend catalogue.
    if (id === "extensions")
      return extensionStore.catalogue.some((e) =>
        `${e.code} ${e.name} ${e.summary}`.toLowerCase().includes(q),
      );

    if (id === "shortcuts")
      return COMMANDS.some((c) => c.label.toLowerCase().includes(q));

    if (id === "about")
      return "about version feedback report issue bug github source license".includes(
        q,
      );

    return false;
  }

  public get visibleCategories(): CategoryMeta[] {
    return SETTINGS_CATEGORIES.filter((c) => this.categoryHasMatches(c.id));
  }

  public get visibleGroups(): {
    section: string;
    categories: CategoryMeta[];
  }[] {
    const visible = this.visibleCategories;
    return SETTINGS_SECTIONS.map((section) => ({
      section,
      categories: visible.filter((c) => c.section === section),
    })).filter((g) => g.categories.length > 0);
  }

  public show() {
    this.open = true;
  }

  public close() {
    this.open = false;
    this.query = "";
  }

  public toggle() {
    if (this.open) this.close();
    else this.show();
  }

  public select(id: CategoryId) {
    this.active = id;
  }

  public resetAll() {
    modeStore.preference = "dark";
    resetThemes();
    editorPrefs.reset();
    displayStore.reset();
    terminalStore.resetPrefs();
    keymap.resetBindings();
  }
}

export const settingsStore = new SettingsStore();
