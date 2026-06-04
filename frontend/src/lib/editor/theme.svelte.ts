import { loadJSON, saveJSON } from "../persist";
import { modeStore } from "../store/mode.svelte";

const STORAGE_KEY = "hart:theme";

export const DARK_THEME = {
  keyword: "#c2a6e1", // Instructions (li, add) — RISC-V Lavender
  register: "#62cbc9", // Registers (x0, a0) — RISC-V Aqua
  directive: "#999999", // Directives (.text) — RISC-V Light Gray
  number: "#fdb515", // Integers / hex — California Gold
  comment: "#666666", // Comments (#) — RISC-V Medium Gray
  string: "#fe9bb1", // Strings ("...") — RISC-V Pink
  background: "#0d0d10", // Editor canvas
};

export const LIGHT_THEME = {
  keyword: "#7e3ff2", // Instructions — deep violet
  register: "#003262", // Registers — Berkeley Blue
  directive: "#6b7280", // Directives — slate gray
  number: "#b06f00", // Integers / hex — deep gold
  comment: "#9aa0a6", // Comments — muted gray
  string: "#c2185b", // Strings — deep pink
  background: "#ffffff", // Editor canvas
};

export type ThemeColors = typeof DARK_THEME;

type Stored = { dark: ThemeColors; light: ThemeColors };

function loadStored(): Stored {
  const raw = loadJSON<unknown>(STORAGE_KEY, null);
  if (raw && typeof raw === "object" && ("dark" in raw || "light" in raw)) {
    const r = raw as Partial<Stored>;
    return {
      dark: { ...DARK_THEME, ...r.dark },
      light: { ...LIGHT_THEME, ...r.light },
    };
  }
  return { dark: { ...DARK_THEME }, light: { ...LIGHT_THEME } };
}

const stored = loadStored();

export const darkTheme = $state<ThemeColors>(stored.dark);
export const lightTheme = $state<ThemeColors>(stored.light);

/** The syntax palette for the currently active light/dark mode. */
export function activeTheme(): ThemeColors {
  return modeStore.mode === "light" ? lightTheme : darkTheme;
}

export function resetActiveTheme() {
  if (modeStore.mode === "light") Object.assign(lightTheme, LIGHT_THEME);
  else Object.assign(darkTheme, DARK_THEME);
}

export function resetThemes() {
  Object.assign(darkTheme, DARK_THEME);
  Object.assign(lightTheme, LIGHT_THEME);
}

$effect.root(() => {
  $effect(() =>
    saveJSON(STORAGE_KEY, {
      dark: { ...darkTheme },
      light: { ...lightTheme },
    }),
  );
});
