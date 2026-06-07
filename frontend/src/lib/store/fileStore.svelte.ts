import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open, save, confirm } from "@tauri-apps/plugin-dialog";
import type { OpenFile } from "../types";
import { logStore } from "./logStore.svelte";
import { loadJSON, saveJSON } from "../persist";
import { EXAMPLES } from "../examples";

const SESSION_KEY = "hart:session";
const LAUNCHED_KEY = "hart:launched";

const basename = (p: string) => p.split(/[/\\]/).pop() ?? "";

type Session = {
  files: OpenFile[];
  activeFileId: string;
};

function firstLaunchSession(): Session {
  const files: OpenFile[] = EXAMPLES.map((ex, i) => ({
    id: `example-${i}`,
    name: ex.name,
    path: null,
    content: ex.content,
    savedContent: ex.content,
  }));
  return { files, activeFileId: files[0]?.id ?? "" };
}

function initialSession(): Session {
  if (!loadJSON<boolean>(LAUNCHED_KEY, false)) {
    saveJSON(LAUNCHED_KEY, true);
    const session = firstLaunchSession();
    saveJSON(SESSION_KEY, session);
    return session;
  }

  const stored = loadJSON<Partial<Session>>(SESSION_KEY, {});
  const files = Array.isArray(stored.files) ? stored.files : [];
  const activeFileId =
    files.find((f) => f.id === stored.activeFileId)?.id ?? files[0]?.id ?? "";
  return { files, activeFileId };
}

class FileStore {
  openFiles = $state<OpenFile[]>([]);
  activeFileId = $state("");
  renamingId = $state<string | null>(null);

  constructor() {
    const session = initialSession();
    this.openFiles = session.files;
    this.activeFileId = session.activeFileId;

    $effect.root(() => {
      $effect(() =>
        saveJSON(SESSION_KEY, {
          files: this.openFiles,
          activeFileId: this.activeFileId,
        } satisfies Session),
      );
    });
  }

  public get activeFile(): OpenFile | undefined {
    return (
      this.openFiles.find((f) => f.id === this.activeFileId) ??
      this.openFiles[0]
    );
  }

  public get hasFiles(): boolean {
    return this.openFiles.length > 0;
  }

  public isDirty(file: OpenFile): boolean {
    return (
      file.content !== file.savedContent ||
      (file.path !== null && basename(file.path) !== file.name)
    );
  }

  public get hasUnsavedChanges(): boolean {
    return this.openFiles.some((f) => this.isDirty(f));
  }

  private uniqueUntitledName(): string {
    const taken = new Set(this.openFiles.map((f) => f.name));
    if (!taken.has("untitled.s")) return "untitled.s";
    for (let n = 1; ; n++) {
      const name = `untitled-${n}.s`;
      if (!taken.has(name)) return name;
    }
  }

  public newFile() {
    const id = `untitled-${Date.now()}`;
    this.openFiles.push({
      id,
      name: this.uniqueUntitledName(),
      path: null,
      content: "",
      savedContent: "",
    });
    this.activeFileId = id;
    this.renamingId = id;
  }

  public startRename(id: string) {
    this.renamingId = id;
  }

  public cancelRename() {
    this.renamingId = null;
  }

  public renameFile(id: string, rawName: string) {
    this.renamingId = null;
    const file = this.openFiles.find((f) => f.id === id);
    if (!file) return;
    const name = rawName.trim();
    if (!name || name === file.name) return;
    file.name = name;
  }

  public async handleOpenFile() {
    const selected = await open({
      multiple: false,
      filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
    });
    if (!selected || typeof selected !== "string") return;
    await this.openPath(selected);
  }

  public async openPath(path: string) {
    const existing = this.openFiles.find((f) => f.path === path);
    if (existing) {
      this.activeFileId = existing.id;
      return;
    }
    try {
      const content = await invoke<string>("read_file", { path });
      const id = `file-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      this.openFiles.push({
        id,
        name: basename(path) || "untitled.s",
        path,
        content,
        savedContent: content,
      });
      this.activeFileId = id;
    } catch (e) {
      logStore.log("error", "FILE", `could not open ${path}: ${e}`);
    }
  }

  private async openPaths(paths: string[]) {
    for (const path of paths) await this.openPath(path);
  }

  public async initLaunchFiles() {
    await listen<string[]>("open-files", (e) => void this.openPaths(e.payload));
    try {
      const launched = await invoke<string[]>("take_launch_files");
      if (launched.length) await this.openPaths(launched);
    } catch (e) {
      logStore.log("error", "FILE", `could not open launched files: ${e}`);
    }
  }

  public async handleSaveFile() {
    const file = this.activeFile;
    if (!file) return;

    try {
      if (file.path !== null && basename(file.path) !== file.name) {
        const dir = file.path.slice(
          0,
          file.path.length - basename(file.path).length,
        );
        const target = dir + file.name;
        await invoke("rename_file", { from: file.path, to: target });
        file.path = target;
      }

      let path = file.path;
      if (!path) {
        const selected = await save({
          defaultPath: file.name,
          filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
        });
        if (!selected) return; // user cancelled
        path = selected;
        file.path = path;
        file.name = basename(path) || file.name;
      }

      await invoke("write_file", { path, contents: file.content });
      file.savedContent = file.content;
    } catch (e) {
      logStore.log("error", "FILE", `could not save file: ${e}`);
    }
  }

  public async closeFile(id: string, e?: Event) {
    if (e) e.stopPropagation();

    const idx = this.openFiles.findIndex((f) => f.id === id);
    if (idx < 0) return;

    if (this.isDirty(this.openFiles[idx])) {
      const discard = await confirm(
        `"${this.openFiles[idx].name}" has unsaved changes. Close without saving?`,
        { title: "Unsaved changes", kind: "warning" },
      );
      if (!discard) return;
    }

    this.openFiles.splice(idx, 1);
    if (this.activeFileId === id) {
      const next = this.openFiles[Math.max(0, idx - 1)];
      this.activeFileId = next ? next.id : "";
    }
  }

  public setActiveFileId(id: string) {
    this.activeFileId = id;
  }
}

export const fileStore = new FileStore();
