import { cpuStore } from "./store/cpuStore.svelte";
import { fileStore } from "./store/fileStore.svelte";

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

function format(combo: string): string {
  const mod = isMac ? "⌘" : "Ctrl";
  return combo
    .split("+")
    .map((p) => {
      const k = p.trim().toLowerCase();
      if (k === "mod") return mod;
      if (k === "alt") return isMac ? "⌥" : "Alt";
      if (k === "shift") return isMac ? "⇧" : "Shift";
      if (/^f\d+$/.test(k)) return k.toUpperCase();
      return k.length === 1 ? k.toUpperCase() : k;
    })
    .join(isMac ? "" : "+");
}

const STORAGE_KEY = "hart:keybindings";

class Keymap {
  overrides = $state<Record<string, string>>({});

  constructor() {
    if (typeof localStorage !== "undefined") {
      try {
        const raw = localStorage.getItem(STORAGE_KEY);
        if (raw) this.overrides = JSON.parse(raw);
      } catch {
        // ignore malformed persisted bindings
      }
    }
  }

  public keysFor(id: string): string {
    if (id in this.overrides) return this.overrides[id];
    return COMMANDS.find((c) => c.id === id)?.defaultKeys ?? "";
  }

  /** display string for a command's current binding, e.g. "⌘S" */
  public describe(id: string): string {
    return format(this.keysFor(id));
  }

  public rebind(id: string, combo: string) {
    this.overrides = { ...this.overrides, [id]: combo };
    this.persist();
  }

  public resetBindings() {
    this.overrides = {};
    this.persist();
  }

  private persist() {
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.overrides));
    }
  }

  public handleKeydown = (e: KeyboardEvent) => {
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
