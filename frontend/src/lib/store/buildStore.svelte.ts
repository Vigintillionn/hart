import type { OpenFile } from "../types";
import { fileStore } from "./fileStore.svelte";
import { loadJSON, saveJSON } from "../persist";

/**
 * How the Compile action decides which open files to assemble and link:
 * - `single`: only the active file (the default).
 * - `all`: every open file, linked together.
 * - `select`: the active file plus an explicitly chosen subset.
 */
export type BuildMode = "single" | "all" | "select";

const MODE_KEY = "hart:buildMode";
const SELECTED_KEY = "hart:buildSelected";

class BuildStore {
  mode = $state<BuildMode>(loadJSON<BuildMode>(MODE_KEY, "single"));
  selected = $state<Set<string>>(new Set(loadJSON<string[]>(SELECTED_KEY, [])));

  constructor() {
    $effect.root(() => {
      $effect(() => saveJSON(MODE_KEY, this.mode));
      $effect(() => saveJSON(SELECTED_KEY, [...this.selected]));
    });
  }

  /** Whether a file will be part of the build (the active file always is). */
  public isIncluded(id: string): boolean {
    if (id === fileStore.activeFileId) return true;
    if (this.mode === "all") return true;
    if (this.mode === "select") return this.selected.has(id);
    return false;
  }

  /** Toggle a file's membership in `select` mode (no-op for the active file). */
  public toggle(id: string) {
    if (id === fileStore.activeFileId) return;
    const next = new Set(this.selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    this.selected = next;
  }

  /** The files the user picked to build: active first, then the rest in editor order. */
  private candidates(): OpenFile[] {
    const active = fileStore.activeFile;
    if (!active) return [];
    const rest = fileStore.openFiles.filter(
      (f) => f.id !== active.id && this.isIncluded(f.id),
    );
    return [active, ...rest];
  }

  /** Names of files that the given files pull in via `.include`. */
  private includeTargetsOf(files: OpenFile[]): Set<string> {
    const targets = new Set<string>();
    const re = /^\s*\.include\s+"([^"]+)"/;
    for (const f of files)
      for (const line of f.content.split("\n")) {
        const m = re.exec(line);
        if (m) targets.add(m[1]);
      }
    return targets;
  }

  /** Names of build files that are reached via `.include` */
  public includedDeps(): Set<string> {
    return this.includeTargetsOf(this.candidates());
  }

  /** Drops the files that are included via `.include` from the build list. */
  public resolveBuildFiles(): OpenFile[] {
    const active = fileStore.activeFile;
    if (!active) return [];
    const cands = this.candidates();
    const deps = this.includeTargetsOf(cands);
    return cands.filter((f) => f.id === active.id || !deps.has(f.name));
  }
}

export const buildStore = new BuildStore();
