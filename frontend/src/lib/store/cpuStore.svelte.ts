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

  /** @returns true once a program has been compiled & loaded */
  get isLoaded() {
    return this.cpuState !== null;
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
          logStore.log(
            "info",
            "BUILD",
            "program assembled & loaded successfully",
          );
          terminalStore.setActiveTab("system");
        } else if (response.type === "error") {
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
    sendToHaskell("load", fileStore.activeFile.content);
  }

  public handleRun() {
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
