import { cpuStore } from "./store/cpuStore.svelte";
import { fileStore } from "./store/fileStore.svelte";
import { loadJSON, saveJSON } from "./persist";

export interface Command {
  id: string;
  label: string;
  defaultKeys: string;
  run: () => void;
  enabled?: () => boolean;
}

const isMac =
  typeof navigator !== "undefined" && /mac/i.test(navigator.userAgent);

const running = () => cpuStore.status === "Running";
const halted = () => cpuStore.status === "Halted";
const live = () => cpuStore.sidecarAlive;

export const COMMANDS: Command[] = [
  {
    id: "compile",
    label: "Compile",
    defaultKeys: "Mod+B",
    run: () => cpuStore.handleLoadProgram(),
    enabled: () => live() && !running(),
  },
  {
    id: "run",
    label: "Run / Continue",
    defaultKeys: "F5",
    run: () => cpuStore.handleRun(),
    enabled: () => live() && cpuStore.isLoaded && !running(),
  },
  {
    id: "pause",
    label: "Pause",
    defaultKeys: "F6",
    run: () => cpuStore.handlePause(),
    enabled: () => live() && running(),
  },
  {
    id: "stepForward",
    label: "Step forward",
    defaultKeys: "F10",
    run: () => cpuStore.handleStepFwd(),
    enabled: () => live() && cpuStore.isLoaded && !running() && !halted(),
  },
  {
    id: "stepBack",
    label: "Step backward",
    defaultKeys: "Shift+F10",
    run: () => cpuStore.handleStepBack(),
    enabled: () => live() && cpuStore.isLoaded && !running(),
  },
  {
    id: "rewind",
    label: "Rewind to start",
    defaultKeys: "Shift+F5",
    run: () => cpuStore.handleRewind(),
    enabled: () => live() && cpuStore.isLoaded && !running(),
  },
  {
    id: "save",
    label: "Save file",
    defaultKeys: "Mod+S",
    run: () => fileStore.handleSaveFile(),
  },
  {
    id: "open",
    label: "Open file",
    defaultKeys: "Mod+O",
    run: () => fileStore.handleOpenFile(),
  },
];

function eventToCombo(e: KeyboardEvent): string {
  const parts: string[] = [];
  if (e.ctrlKey || e.metaKey) parts.push("mod");
  if (e.altKey) parts.push("alt");
  if (e.shiftKey) parts.push("shift");
  let key = e.key.toLowerCase();
  if (key === " ") key = "space";
  parts.push(key);
  return parts.join("+");
}

function canon(combo: string): string {
  let mod = false;
  let alt = false;
  let shift = false;
  let key = "";
  for (const raw of combo.toLowerCase().split("+")) {
    const p = raw.trim();
    if (["mod", "cmd", "meta", "ctrl", "control"].includes(p)) mod = true;
    else if (["alt", "option", "opt"].includes(p)) alt = true;
    else if (p === "shift") shift = true;
    else if (p) key = p;
  }
  const parts: string[] = [];
  if (mod) parts.push("mod");
  if (alt) parts.push("alt");
  if (shift) parts.push("shift");
  if (key) parts.push(key);
  return parts.join("+");
}

function formatPart(part: string): string {
  const k = part.trim().toLowerCase();
  if (k === "mod") return isMac ? "⌘" : "Ctrl";
  if (k === "alt") return isMac ? "⌥" : "Alt";
  if (k === "shift") return "⇧";
  if (k === "space") return "␣";
  if (k === "arrowup") return "↑";
  if (k === "arrowdown") return "↓";
  if (k === "arrowleft") return "←";
  if (k === "arrowright") return "→";
  if (k === "escape") return "Esc";
  if (/^f\d+$/.test(k)) return k.toUpperCase();
  return k.length === 1 ? k.toUpperCase() : k;
}

const GLYPHS = new Set(["⌘", "⌥", "⇧", "␣"]);
export function isGlyph(token: string): boolean {
  return GLYPHS.has(token);
}

export const ARROW_PATHS: Record<string, string> = {
  "↑": "M12 19V6M7 11l5-5 5 5",
  "↓": "M12 5v13M7 13l5 5 5-5",
  "←": "M19 12H6M11 7l-5 5 5 5",
  "→": "M5 12h13M13 7l5 5-5 5",
};

function format(combo: string): string {
  return combo
    .split("+")
    .map(formatPart)
    .join(isMac ? "" : "+");
}

export function comboParts(combo: string): string[] {
  return combo.split("+").filter(Boolean).map(formatPart);
}

const STORAGE_KEY = "hart:keybindings";

class Keymap {
  overrides = $state<Record<string, string>>(
    loadJSON<Record<string, string>>(STORAGE_KEY, {}),
  );

  /** id of the command currently listening for a new binding, or null. */
  capturing = $state<string | null>(null);

  public keysFor(id: string): string {
    if (id in this.overrides) return this.overrides[id];
    return COMMANDS.find((c) => c.id === id)?.defaultKeys ?? "";
  }

  /** display string for a command's current binding, e.g. "⌘S" */
  public describe(id: string): string {
    return format(this.keysFor(id));
  }

  /** display tokens for a command's binding, e.g. ["Ctrl", "B"] */
  public partsFor(id: string): string[] {
    return comboParts(this.keysFor(id));
  }

  public rebind(id: string, combo: string) {
    this.overrides = { ...this.overrides, [id]: combo };
    this.persist();
  }

  public resetBinding(id: string) {
    const { [id]: _removed, ...rest } = this.overrides;
    this.overrides = rest;
    this.persist();
  }

  public resetBindings() {
    this.overrides = {};
    this.persist();
  }

  public startCapture(id: string) {
    this.capturing = id;
  }

  public cancelCapture() {
    this.capturing = null;
  }

  public captureKeydown(e: KeyboardEvent): boolean {
    if (!this.capturing) return false;
    if (e.key === "Escape") {
      this.cancelCapture();
      return true;
    }
    if (["Shift", "Control", "Alt", "Meta"].includes(e.key)) return true;
    this.rebind(this.capturing, eventToCombo(e));
    this.cancelCapture();
    return true;
  }

  private persist() {
    saveJSON(STORAGE_KEY, this.overrides);
  }

  public handleKeydown = (e: KeyboardEvent) => {
    if (this.capturing) return;
    const combo = eventToCombo(e);
    for (const cmd of COMMANDS) {
      if (canon(this.keysFor(cmd.id)) !== combo) continue;
      if (cmd.enabled && !cmd.enabled()) {
        e.preventDefault();
        return;
      }
      e.preventDefault();
      cmd.run();
      return;
    }
  };
}

export const keymap = new Keymap();
