import { loadJSON, saveJSON } from "../persist";

const STORAGE_KEY = "hart:mode";

export type Mode = "dark" | "light";

export const modeStore = $state<{ mode: Mode }>({
  mode: loadJSON<Mode>(STORAGE_KEY, "dark"),
});

function apply(mode: Mode) {
  if (typeof document === "undefined") return;
  document.documentElement.dataset.theme = mode;
}

apply(modeStore.mode);

export function toggleMode() {
  modeStore.mode = modeStore.mode === "dark" ? "light" : "dark";
}

$effect.root(() => {
  $effect(() => {
    apply(modeStore.mode);
    saveJSON(STORAGE_KEY, modeStore.mode);
  });
});
