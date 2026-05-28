import { open, save } from "@tauri-apps/plugin-dialog";
import { readTextFile, writeTextFile } from "@tauri-apps/plugin-fs";
import type { OpenFile } from "./types";

class FileStore {
  openFiles = $state<OpenFile[]>([
    {
      id: "default",
      name: "untitled.s",
      path: null,
      content: ".text\nmain:\n  li a0, 5\n  li a7, 93\n  ecall",
    },
  ]);
  activeFileId = $state("default");

  public get activeFile() {
    return (
      this.openFiles.find((f) => f.id === this.activeFileId) ||
      this.openFiles[0]
    );
  }

  public async handleOpenFile() {
    const selected = await open({
      multiple: false,
      filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
    });

    if (selected && typeof selected === "string") {
      const content = await readTextFile(selected);
      const name = selected.split(/[\/\\]/).pop() || "untitled.s";
      const id = Date.now().toString();

      this.openFiles.push({ id, name, path: selected, content });
      this.activeFileId = id;
    }
  }

  public async handleSaveFile() {
    if (!this.activeFile) return;

    if (this.activeFile.path) {
      await writeTextFile(this.activeFile.path, this.activeFile.content);
    } else {
      const selected = await save({
        filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
      });
      if (selected) {
        await writeTextFile(selected, this.activeFile.content);
        this.activeFile.path = selected;
        this.activeFile.name =
          selected.split(/[\/\\]/).pop() || this.activeFile.name;
      }
    }
  }

  public closeFile(id: string, e?: Event) {
    if (e) e.stopPropagation();
    if (this.openFiles.length === 1) return; // don't close last file

    const idx = this.openFiles.findIndex((f) => f.id === id);
    if (idx > -1) {
      this.openFiles.splice(idx, 1);
      if (this.activeFileId === id) {
        this.activeFileId = this.openFiles[Math.max(0, idx - 1)].id;
      }
    }
  }

  public setActiveFileId(id: string) {
    this.activeFileId = id;
  }
}

export const fileStore = new FileStore();
