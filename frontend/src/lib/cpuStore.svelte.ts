import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { CpuState } from "../bindings/CpuState";
import type { EmulatorResponse } from "../bindings/EmulatorResponse";
import type { SourceMap } from "./types";
import { terminalStore } from "./terminalStore.svelte";
import { fileStore } from "./fileStore.svelte";
import { sendToHaskell } from "./util";

class CpuStore {
  cpuState = $state<CpuState | null>(null);
  sourceMap = $state<SourceMap>([]);
  unlisten: UnlistenFn | null = null;

  public async initListener() {
    if (this.unlisten) return;

    this.unlisten = await listen<EmulatorResponse>(
      "emulator-update",
      (event) => {
        const response = event.payload;

        if (response.type === "state") {
          this.cpuState = response.data;
          if ((this.cpuState as any).outputBuffer) {
            terminalStore.program.set((this.cpuState as any).outputBuffer);
          } else {
            terminalStore.program.clear();
          }
        } else if (response.type === "loaded") {
          this.cpuState = response.state;
          this.sourceMap = response.sourceMap;
          terminalStore.system.log(`[SUCCESS]: Program loaded successfully.`);
          terminalStore.setActiveTab("program");
        } else if (response.type === "error") {
          terminalStore.system.log(`[ERROR]: ${response.message}`);
          terminalStore.setActiveTab("system");
        } else if (response.type === "need_input") {
          if (this.cpuState) {
            this.cpuState.status = "WaitingForInput";
          }
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
    terminalStore.setActiveTab("system");
    terminalStore.system.log("> Compiling program...");
    sendToHaskell("load", fileStore.activeFile.content);
  }

  public handleRun() {
    sendToHaskell("run");
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
