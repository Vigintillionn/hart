import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { CpuState } from "../../bindings/CpuState";
import type { EmulatorResponse } from "../../bindings/EmulatorResponse";
import type { SourceMap, DisasmMap } from "../types";
import { terminalStore } from "./terminalStore.svelte";
import { logStore } from "./logStore.svelte";
import { fileStore } from "./fileStore.svelte";
import { sendToHaskell } from "../util";

class CpuStore {
  cpuState = $state<CpuState | null>(null);
  sourceMap = $state<SourceMap>([]);
  disasmMap = $state<DisasmMap>([]);
  unlisten: UnlistenFn | null = null;

  /** snapshot of the file (id + content) that the emulator currently holds */
  loadedSnapshot = $state<{ fileId: string; content: string } | null>(null);
  /** snapshot of the in-flight `load` command, promoted on the `loaded` event */
  private pendingSnapshot: { fileId: string; content: string } | null = null;
  /** set when a `run` should fire automatically after a recompile succeeds */
  private runAfterLoad = false;

  /** @returns true once a program has been compiled & loaded */
  get isLoaded() {
    return this.cpuState !== null;
  }

  /**
   * @returns true when the active file differs from what the emulator has
   * loaded (edited since the last compile, or a different file is focused).
   * Used to recompile before running so we never execute stale machine code.
   */
  get isDirty() {
    if (!this.loadedSnapshot) return false;
    const f = fileStore.activeFile;
    return (
      f.id !== this.loadedSnapshot.fileId ||
      f.content !== this.loadedSnapshot.content
    );
  }

  get status() {
    return this.cpuState?.status ?? null;
  }

  public async initListener() {
    if (this.unlisten) return;

    this.unlisten = await listen<EmulatorResponse>(
      "emulator-update",
      (event) => {
        const response = event.payload;

        if (response.type === "state") {
          this.cpuState = response.data;
          const out = (this.cpuState as any).outputBuffer;
          if (out) terminalStore.program.set(out);
          else terminalStore.program.clear();
        } else if (response.type === "loaded") {
          this.cpuState = response.state;
          this.sourceMap = response.sourceMap;
          this.disasmMap = response.disasmMap;
          this.loadedSnapshot = this.pendingSnapshot;
          logStore.log(
            "info",
            "BUILD",
            "program assembled & loaded successfully",
          );
          terminalStore.setActiveTab("system");
          if (this.runAfterLoad) {
            this.runAfterLoad = false;
            sendToHaskell("run");
          }
        } else if (response.type === "error") {
          this.runAfterLoad = false;
          logStore.log("error", "ASM", response.message);
          terminalStore.setActiveTab("system");
        } else if (response.type === "need_input") {
          if (this.cpuState) this.cpuState.status = "WaitingForInput";
          terminalStore.setActiveTab("program");
        }
      },
    );
  }

  public cleanup() {
    if (this.unlisten) {
      this.unlisten();
      this.unlisten = null;
    }
  }

  public handleLoadProgram() {
    logStore.log("info", "BUILD", "compiling program…");
    terminalStore.setActiveTab("system");
    const f = fileStore.activeFile;
    this.pendingSnapshot = { fileId: f.id, content: f.content };
    sendToHaskell("load", f.content);
  }

  public handleRun() {
    if (this.isDirty) {
      this.runAfterLoad = true;
      this.handleLoadProgram();
      return;
    }
    sendToHaskell("run");
  }

  public handlePause() {
    sendToHaskell("pause");
  }

  public handleStepFwd() {
    sendToHaskell("step_forward");
  }

  public handleStepBack() {
    sendToHaskell("step_back");
  }

  public handleRewind() {
    sendToHaskell("rewind");
  }

  public submitInput(text: string) {
    sendToHaskell("input", text);
  }
}

export const cpuStore = new CpuStore();
