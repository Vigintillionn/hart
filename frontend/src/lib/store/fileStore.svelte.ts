import { open, save, confirm } from "@tauri-apps/plugin-dialog";
import { readTextFile, writeTextFile } from "@tauri-apps/plugin-fs";
import type { OpenFile } from "../types";
import { logStore } from "./logStore.svelte";

const STARTER = `# Welcome to HART - a RISC-V (RV32IM) time-travel debugger.
#
# Press Compile to assemble and Run to execute this program, then use the
# step controls to walk through it forwards AND backwards while
# the registers and memory update live on the right.

.data
msg:     .string "sum(1..5) = "
newline: .string "\\n"

.text
main:
        la      a0, msg         # address of the string
        li      a7, 4           # syscall 4: print_string
        ecall

        li      t0, 0           # t0 = running sum
        li      t1, 1           # t1 = i (the counter)
        li      t2, 6           # stop once i reaches 6
loop:
        add     t0, t0, t1      # sum += i
        addi    t1, t1, 1       # i++
        blt     t1, t2, loop    # repeat while i < 6

        mv      a0, t0          # print the result...
        li      a7, 1           # syscall 1: print_int
        ecall

        la      a0, newline     # print a newline
        li      a7, 4           # syscall 4: print_string
        ecall

        li      a7, 10          # syscall 10: exit
        ecall
`;

class FileStore {
  openFiles = $state<OpenFile[]>([
    {
      id: "default",
      name: "untitled.s",
      path: null,
      content: STARTER,
      savedContent: STARTER,
    },
  ]);
  activeFileId = $state("default");

  public get activeFile() {
    return (
      this.openFiles.find((f) => f.id === this.activeFileId) ||
      this.openFiles[0]
    );
  }

  /** @returns true if the file has edits not yet written to disk */
  public isDirty(file: OpenFile): boolean {
    return file.content !== file.savedContent;
  }

  public get hasUnsavedChanges(): boolean {
    return this.openFiles.some((f) => this.isDirty(f));
  }

  public async handleOpenFile() {
    try {
      const selected = await open({
        multiple: false,
        filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
      });
      if (!selected || typeof selected !== "string") return;

      const content = await readTextFile(selected);
      const name = selected.split(/[/\\]/).pop() || "untitled.s";
      const id = Date.now().toString();

      this.openFiles.push({
        id,
        name,
        path: selected,
        content,
        savedContent: content,
      });
      this.activeFileId = id;
    } catch (e) {
      logStore.log("error", "FILE", `could not open file: ${e}`);
    }
  }

  public async handleSaveFile() {
    const file = this.activeFile;
    if (!file) return;

    try {
      let path = file.path;
      if (!path) {
        const selected = await save({
          filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
        });
        if (!selected) return; // user cancelled
        path = selected;
      }

      await writeTextFile(path, file.content);
      file.path = path;
      file.name = path.split(/[/\\]/).pop() || file.name;
      file.savedContent = file.content;
    } catch (e) {
      logStore.log("error", "FILE", `could not save file: ${e}`);
    }
  }

  public async closeFile(id: string, e?: Event) {
    if (e) e.stopPropagation();
    if (this.openFiles.length === 1) return; // don't close last file

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
      this.activeFileId = this.openFiles[Math.max(0, idx - 1)].id;
    }
  }

  public setActiveFileId(id: string) {
    this.activeFileId = id;
  }
}

export const fileStore = new FileStore();
