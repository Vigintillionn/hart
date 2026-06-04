import { loadJSON, saveJSON } from "../persist";

const STORAGE_KEY = "hart:mode";

export type Mode = "dark" | "light";
export type ThemePreference = "system" | "light" | "dark";

function systemPrefersDark(): boolean {
  if (typeof window === "undefined" || !window.matchMedia) return true;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function loadPreference(): ThemePreference {
  const raw = loadJSON<string>(STORAGE_KEY, "dark");
  return raw === "system" || raw === "light" || raw === "dark" ? raw : "dark";
}

function apply(mode: Mode) {
  if (typeof document === "undefined") return;
  document.documentElement.dataset.theme = mode;
}

class ModeStore {
  preference = $state<ThemePreference>(loadPreference());
  private systemDark = $state(systemPrefersDark());

  public get mode(): Mode {
    if (this.preference === "system") return this.systemDark ? "dark" : "light";
    return this.preference;
  }

  constructor() {
    if (typeof window !== "undefined" && window.matchMedia) {
      window
        .matchMedia("(prefers-color-scheme: dark)")
        .addEventListener("change", (e) => (this.systemDark = e.matches));
    }
    apply(this.mode);

    $effect.root(() => {
      $effect(() => {
        apply(this.mode);
        saveJSON(STORAGE_KEY, this.preference);
      });
    });
  }
}

export const modeStore = new ModeStore();

export function toggleMode() {
  modeStore.preference = modeStore.mode === "dark" ? "light" : "dark";
}
