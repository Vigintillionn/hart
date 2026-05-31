import { loadJSON, saveJSON } from "../persist";

const STORAGE_KEY = "hart:theme";

export const DEFAULT_THEME = {
  keyword: "#c2a6e1", // Instructions (li, add) — RISC-V Lavender
  register: "#62cbc9", // Registers (x0, a0) — RISC-V Aqua
  directive: "#999999", // Directives (.text) — RISC-V Light Gray
  number: "#fdb515", // Integers / hex — California Gold
  comment: "#666666", // Comments (#) — RISC-V Medium Gray
  string: "#fe9bb1", // Strings ("...") — RISC-V Pink
  background: "#0d0d10", // Editor canvas
};

export type ThemeColors = typeof DEFAULT_THEME;

export const themeColors = $state<ThemeColors>({
  ...DEFAULT_THEME,
  ...loadJSON<Partial<ThemeColors>>(STORAGE_KEY, {}),
});

export function resetTheme() {
  Object.assign(themeColors, DEFAULT_THEME);
}

$effect.root(() => {
  $effect(() => saveJSON(STORAGE_KEY, { ...themeColors }));
});
