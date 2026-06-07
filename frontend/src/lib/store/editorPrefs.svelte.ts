import { loadJSON, saveJSON } from "../persist";

const STORAGE_KEY = "hart:editorPrefs";

export type LineNumbers = "on" | "relative" | "off";

export interface EditorPrefs {
  fontFamily: string;
  fontSize: number;
  tabWidth: number;
  insertSpaces: boolean;
  lineNumbers: LineNumbers;
  wordWrap: boolean;
  renderWhitespace: boolean;
  minimap: boolean;
  hoverInstructions: boolean;
  hoverDirectives: boolean;
  hoverRegisters: boolean;
  hoverCsrs: boolean;
}

export const DEFAULT_PREFS: EditorPrefs = {
  fontFamily: "JetBrains Mono",
  fontSize: 13,
  tabWidth: 4,
  insertSpaces: true,
  lineNumbers: "on",
  wordWrap: false,
  renderWhitespace: false,
  minimap: false,
  hoverInstructions: true,
  hoverDirectives: true,
  hoverRegisters: true,
  hoverCsrs: true,
};

export const FONT_FAMILIES: string[] = [
  "JetBrains Mono",
  "Geist Mono",
  "Fira Code",
  "IBM Plex Mono",
  "Source Code Pro",
  "Roboto Mono",
  "monospace",
];

export const FONT_SIZES = [11, 12, 13, 14, 16, 18];

export function fontStack(family: string): string {
  if (family === "monospace") return "ui-monospace, monospace";
  return `'${family}', ui-monospace, monospace`;
}

class EditorPrefsStore {
  fontFamily = $state(DEFAULT_PREFS.fontFamily);
  fontSize = $state(DEFAULT_PREFS.fontSize);
  tabWidth = $state(DEFAULT_PREFS.tabWidth);
  insertSpaces = $state(DEFAULT_PREFS.insertSpaces);
  lineNumbers = $state<LineNumbers>(DEFAULT_PREFS.lineNumbers);
  wordWrap = $state(DEFAULT_PREFS.wordWrap);
  renderWhitespace = $state(DEFAULT_PREFS.renderWhitespace);
  minimap = $state(DEFAULT_PREFS.minimap);
  hoverInstructions = $state(DEFAULT_PREFS.hoverInstructions);
  hoverDirectives = $state(DEFAULT_PREFS.hoverDirectives);
  hoverRegisters = $state(DEFAULT_PREFS.hoverRegisters);
  hoverCsrs = $state(DEFAULT_PREFS.hoverCsrs);

  constructor() {
    const stored = loadJSON<Partial<EditorPrefs>>(STORAGE_KEY, {});
    Object.assign(this, { ...DEFAULT_PREFS, ...stored });

    $effect.root(() => {
      $effect(() => saveJSON(STORAGE_KEY, this.snapshot()));
    });
  }

  private snapshot(): EditorPrefs {
    return {
      fontFamily: this.fontFamily,
      fontSize: this.fontSize,
      tabWidth: this.tabWidth,
      insertSpaces: this.insertSpaces,
      lineNumbers: this.lineNumbers,
      wordWrap: this.wordWrap,
      renderWhitespace: this.renderWhitespace,
      minimap: this.minimap,
      hoverInstructions: this.hoverInstructions,
      hoverDirectives: this.hoverDirectives,
      hoverRegisters: this.hoverRegisters,
      hoverCsrs: this.hoverCsrs,
    };
  }

  public reset() {
    Object.assign(this, DEFAULT_PREFS);
  }
}

export const editorPrefs = new EditorPrefsStore();
