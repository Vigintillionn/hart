import type { IconName } from "../types";
import { extensionStore } from "./extensionStore.svelte";

/** The categories shown in the settings window sidebar. */
export type CategoryId = "appearance" | "editor" | "extensions";

export interface CategoryMeta {
  id: CategoryId;
  label: string;
  icon: IconName;
}

export interface SettingDescriptor {
  id: string;
  category: CategoryId;
  title: string;
  description?: string;
  keywords?: string[];
}

export const SETTINGS_CATEGORIES: CategoryMeta[] = [
  { id: "appearance", label: "Appearance", icon: "sun" },
  { id: "editor", label: "Editor", icon: "pencil" },
  { id: "extensions", label: "ISA Extensions", icon: "chip" },
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

    return false;
  }

  public get visibleCategories(): CategoryMeta[] {
    return SETTINGS_CATEGORIES.filter((c) => this.categoryHasMatches(c.id));
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
}

export const settingsStore = new SettingsStore();
