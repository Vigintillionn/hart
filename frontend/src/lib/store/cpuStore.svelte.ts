import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { CpuState } from "../../bindings/CpuState";
import type { EmulatorResponse } from "../../bindings/EmulatorResponse";
import type { Severity } from "../../bindings/Severity";
import type { SourceMap, DisasmMap, CodeMap, TextRow } from "../types";
import { terminalStore } from "./terminalStore.svelte";
import { logStore, type LogLevel } from "./logStore.svelte";
import { fileStore } from "./fileStore.svelte";
import { extensionStore } from "./extensionStore.svelte";
import { sendToHaskell } from "../util";
import {
  emulatorErrorLine,
  emulatorErrorTag,
  formatEmulatorError,
  formatSystemEvent,
  systemEventTag,
} from "../errorFormat";

function severityToLevel(sev: Severity): LogLevel {
  switch (sev) {
    case "warning":
      return "warn";
    case "error":
      return "error";
    default:
      return "info";
  }
}

class CpuStore {
  cpuState = $state<CpuState | null>(null);
  sourceMap = $state<SourceMap>([]);
  disasmMap = $state<DisasmMap>([]);
  codeMap = $state<CodeMap>([]);
  sourceLineMap = $derived(new Map(this.sourceMap));
  disasmTextMap = $derived(new Map(this.disasmMap));
  breakpoints = $state(new Set<number>());
  textRows = $derived.by<TextRow[]>(() => {
    const lines = (this.loadedSnapshot?.content ?? "").split("\n");
    const codeByAddr = new Map(this.codeMap);
    let prevLine = -1;
    return this.disasmMap.map(([addr, basic]) => {
      const line = this.sourceLineMap.get(addr) ?? 0;
      const source = line !== prevLine ? (lines[line - 1] ?? "").trim() : null;
      prevLine = line;
      return { addr, code: codeByAddr.get(addr) ?? 0, basic, line, source };
    });
  });
  lineToAddrs = $derived.by(() => {
    const m = new Map<number, number[]>();
    for (const [addr, line] of this.sourceMap) {
      const arr = m.get(line);
      if (arr) arr.push(addr);
      else m.set(line, [addr]);
    }
    for (const arr of m.values()) arr.sort((a, b) => a - b);
    return m;
  });
  breakpointLines = $derived.by(() => {
    const s = new Set<number>();
    for (const addr of this.breakpoints) {
      const line = this.sourceLineMap.get(addr);
      if (line !== undefined) s.add(line);
    }
    return s;
  });
  sidecarAlive = $state(true);
  compileError = $state<{
    fileId: string;
    line: number | null;
    message: string;
  } | null>(null);
  unlisten: UnlistenFn | null = null;
  unlistenSidecar: UnlistenFn | null = null;

  /** snapshot of the file (id + content) that the emulator currently holds */
  loadedSnapshot = $state<{ fileId: string; content: string } | null>(null);
  /** snapshot of the in-flight `load` command, promoted on the `loaded` event */
  private pendingSnapshot: { fileId: string; content: string } | null = null;
  /** set when a `run` should fire automatically after a recompile succeeds */
  private runAfterLoad = false;
  private systemLogShown = 0;
  /**
   * Accumulated memory, keyed by byte address. The backend ships full memory
   * only on `loaded`/full `state`; forward `state_delta` messages carry just
   * the changed bytes, which we merge here so `cpuState.mem` stays a complete
   * snapshot for the UI.
   */
  private memMap = new Map<bigint, number>();

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

    this.unlistenSidecar = await listen<{ code: number | null }>(
      "sidecar-exit",
      (event) => {
        this.sidecarAlive = false;
        if (this.cpuState) this.cpuState.status = "Halted";
        logStore.log(
          "error",
          "EMU",
          `emulator process exited${
            event.payload?.code != null ? ` (code ${event.payload.code})` : ""
          } — your code is safe; save your work and restart the app`,
        );
        terminalStore.setActiveTab("system");
      },
    );

    this.unlisten = await listen<EmulatorResponse>(
      "emulator-update",
      (event) => {
        const response = event.payload;

        if (response.type === "state") {
          // full snapshot: reset the accumulated memory to match
          this.memMap = new Map(response.data.mem);
          this.commitState(response.data);
        } else if (response.type === "state_delta") {
          // incremental: merge changed bytes + appended console onto the base
          const prev = this.cpuState;
          if (!prev) return; // a delta with no base should never arrive
          for (const [addr, val] of response.memDelta)
            this.memMap.set(addr, val);
          this.commitState({
            pc: response.pc,
            regs: response.regs,
            csrs: response.csrs,
            cycles: response.cycles,
            status: response.status,
            heapTop: response.heapTop,
            systemLog: response.systemLog,
            mem: [...this.memMap.entries()],
            outputBuffer: prev.outputBuffer + response.outputAppend,
          });
        } else if (response.type === "loaded") {
          this.memMap = new Map(response.state.mem);
          this.cpuState = response.state;
          this.sourceMap = response.sourceMap;
          this.disasmMap = response.disasmMap;
          this.codeMap = response.codeMap;
          this.loadedSnapshot = this.pendingSnapshot;
          this.compileError = null;
          this.systemLogShown = 0;
          this.mirrorSystemLog();
          terminalStore.setActiveTab("system");
          if (this.breakpoints.size) {
            // a recompile can move instructions; drop breakpoints whose address
            // is no longer the start of an instruction before re-arming them.
            const valid = new Set(this.sourceMap.map(([addr]) => addr));
            const pruned = new Set(
              [...this.breakpoints].filter((a) => valid.has(a)),
            );
            if (pruned.size !== this.breakpoints.size)
              this.breakpoints = pruned;
            this.sendBreakpoints();
          }
          if (this.runAfterLoad) {
            this.runAfterLoad = false;
            sendToHaskell("run");
          }
        } else if (response.type === "error") {
          this.runAfterLoad = false;
          if (response.error) {
            const message = formatEmulatorError(response.error);
            const line = emulatorErrorLine(response.error);
            logStore.log(
              "error",
              emulatorErrorTag(response.error),
              line !== null ? `At line ${line}: ${message}` : message,
            );
            const fileId =
              this.pendingSnapshot?.fileId ?? fileStore.activeFile.id;
            this.compileError = { fileId, line, message };
          } else {
            logStore.log("error", "EMU", response.message ?? "Unknown error");
          }
          terminalStore.setActiveTab("system");
        } else if (response.type === "log") {
          logStore.log(
            severityToLevel(response.severity),
            response.tag,
            response.message,
          );
        } else if (response.type === "need_input") {
          if (this.cpuState) this.cpuState.status = "WaitingForInput";
          terminalStore.setActiveTab("program");
        } else if (response.type === "extensions") {
          extensionStore.setCatalogue(response.data);
        }
      },
    );

    sendToHaskell("get_extensions");
  }

  /** Adopt a new CPU state and mirror its console + system log to the UI. */
  private commitState(state: CpuState) {
    this.cpuState = state;
    const out = state.outputBuffer;
    if (out) terminalStore.program.set(out);
    else terminalStore.program.clear();
    this.mirrorSystemLog();
  }

  private mirrorSystemLog() {
    const log = this.cpuState?.systemLog ?? [];
    if (log.length <= this.systemLogShown) return;

    let sawError = false;
    for (let i = this.systemLogShown; i < log.length; i++) {
      const ev = log[i];
      const level = severityToLevel(ev.severity);
      logStore.log(level, systemEventTag(ev), formatSystemEvent(ev));
      if (level === "error") sawError = true;
    }
    this.systemLogShown = log.length;

    if (sawError) terminalStore.setActiveTab("system");
  }

  public cleanup() {
    if (this.unlisten) {
      this.unlisten();
      this.unlisten = null;
    }
    if (this.unlistenSidecar) {
      this.unlistenSidecar();
      this.unlistenSidecar = null;
    }
  }

  public handleLoadProgram() {
    // The emulator narrates the build pipeline itself ("Compiling...", etc.);
    // we just surface the system console immediately on user action.
    terminalStore.setActiveTab("system");
    this.compileError = null;
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

  public toggleBreakpointAddr(addr: number) {
    const next = new Set(this.breakpoints);
    if (next.has(addr)) next.delete(addr);
    else next.add(addr);
    this.breakpoints = next;
    this.sendBreakpoints();
  }

  public toggleBreakpointLine(line: number) {
    const addrs = this.lineToAddrs.get(line);
    if (!addrs?.length) return; // no instruction on this line
    const next = new Set(this.breakpoints);
    if (addrs.some((a) => next.has(a))) {
      for (const a of addrs) next.delete(a);
    } else {
      next.add(addrs[0]);
    }
    this.breakpoints = next;
    this.sendBreakpoints();
  }

  private sendBreakpoints() {
    sendToHaskell("set_breakpoints", [...this.breakpoints]);
  }
}

export const cpuStore = new CpuStore();
