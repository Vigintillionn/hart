import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { CpuState } from "../../bindings/CpuState";
import type { EmulatorResponse } from "../../bindings/EmulatorResponse";
import type { Severity } from "../../bindings/Severity";
import type {
  SourceMap,
  DisasmMap,
  CodeMap,
  TextRow,
  DisplayRow,
} from "../types";
import { terminalStore } from "./terminalStore.svelte";
import { logStore, type LogLevel } from "./logStore.svelte";
import { fileStore } from "./fileStore.svelte";
import { buildStore } from "./buildStore.svelte";
import { extensionStore } from "./extensionStore.svelte";
import { isaStore } from "./isaStore.svelte";
import { sendToHaskell } from "../util";
import {
  emulatorErrorFile,
  emulatorErrorLine,
  emulatorErrorTag,
  formatEmulatorError,
  formatSystemEvent,
  systemEventTag,
} from "../errorFormat";

/** A file as compiled, in link order. */
type BuildFile = { name: string; content: string };

type LoadSnapshot = {
  fileId: string;
  content: string;
  files: BuildFile[];
  entry: string[];
};

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
  // global instruction-address -> source line / file (every file in the build)
  sourceLineMap = $derived(new Map(this.sourceMap.map(([a, l]) => [a, l])));
  sourceFileMap = $derived(new Map(this.sourceMap.map(([a, , f]) => [a, f])));
  disasmTextMap = $derived(new Map(this.disasmMap));
  breakpoints = $state(new Set<number>());
  /** Name of the file shown in the editor; highlighting/breakpoints scope to it */
  private get activeFileName(): string {
    return fileStore.activeFile?.name ?? "";
  }
  activeFilePcToLine = $derived.by(() => {
    const name = this.activeFileName;
    const m = new Map<number, number>();
    for (const [addr, line, file] of this.sourceMap)
      if (file === name) m.set(addr, line);
    return m;
  });
  textRows = $derived.by<TextRow[]>(() => {
    const byFile = new Map(
      (this.loadedSnapshot?.files ?? []).map(
        (f) => [f.name, f.content.split("\n")] as const,
      ),
    );
    const codeByAddr = new Map(this.codeMap);
    let prevLine = -1;
    let prevFile = "";
    return this.disasmMap.map(([addr, basic]) => {
      const line = this.sourceLineMap.get(addr) ?? 0;
      const file = this.sourceFileMap.get(addr) ?? "";
      const fresh = line !== prevLine || file !== prevFile;
      const source = fresh ? (byFile.get(file)?.[line - 1] ?? "").trim() : null;
      prevLine = line;
      prevFile = file;
      return { addr, code: codeByAddr.get(addr) ?? 0, basic, line, source };
    });
  });
  textRowsDisplay = $derived.by<DisplayRow[]>(() => {
    const out: DisplayRow[] = [];
    let prevEnd: number | null = null;
    for (const row of this.textRows) {
      if (prevEnd !== null && row.addr > prevEnd) {
        out.push({ kind: "pad", addr: prevEnd, bytes: row.addr - prevEnd });
      }
      out.push({ kind: "instr", ...row });
      prevEnd = row.addr + 4;
    }
    return out;
  });
  // line -> addresses, for the active file only (line numbers collide across
  // files, so a breakpoint toggled in the editor must resolve within its file)
  lineToAddrs = $derived.by(() => {
    const m = new Map<number, number[]>();
    for (const [addr, line] of this.activeFilePcToLine) {
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
      const line = this.activeFilePcToLine.get(addr);
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

  /** snapshot of the build the emulator currently holds (entry + linked files) */
  loadedSnapshot = $state<LoadSnapshot | null>(null);
  /** snapshot of the in-flight `load` command, promoted on the `loaded` event */
  private pendingSnapshot: LoadSnapshot | null = null;
  /** set when a `run` should fire automatically after a recompile succeeds */
  private runAfterLoad = false;
  private systemLogShown = 0;
  private syscallEntries = new Map<number, { id: number; msg: string }>();
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
    const snap = this.loadedSnapshot;
    if (!snap) return false;
    const f = fileStore.activeFile;
    if (!f) return false;
    if (f.id !== snap.fileId) return true; // entry changed
    const entry = buildStore.resolveBuildFiles().map((bf) => bf.name);
    if (entry.length !== snap.entry.length) return true;
    if (entry.some((n, i) => n !== snap.entry[i])) return true;
    const pool = fileStore.openFiles;
    if (pool.length !== snap.files.length) return true;
    return pool.some(
      (pf, i) =>
        pf.name !== snap.files[i].name || pf.content !== snap.files[i].content,
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
          } - your code is safe; save your work and restart the app`,
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
          this.syscallEntries.clear();
          this.mirrorSystemLog();
          terminalStore.autoSwitch("system");
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
            // route the marker to the file the error names (multi-file builds),
            // falling back to the entry file when it carries no provenance
            const errFile = emulatorErrorFile(response.error);
            const named = errFile
              ? fileStore.openFiles.find((f) => f.name === errFile)?.id
              : undefined;
            const fileId =
              named ??
              this.pendingSnapshot?.fileId ??
              fileStore.activeFile?.id ??
              "";
            this.compileError = { fileId, line, message };
          } else {
            logStore.log("error", "EMU", response.message ?? "Unknown error");
          }
          terminalStore.autoSwitch("system");
        } else if (response.type === "log") {
          logStore.log(
            severityToLevel(response.severity),
            response.tag,
            response.message,
          );
        } else if (response.type === "need_input") {
          if (this.cpuState) this.cpuState.status = "WaitingForInput";
          terminalStore.autoSwitch("program");
        } else if (response.type === "extensions") {
          extensionStore.setCatalogue(response.data);
        } else if (response.type === "instruction_set") {
          isaStore.setCatalogue(
            response.formats,
            response.instructions,
            response.pseudos,
            response.syscalls,
            response.directives,
            response.csrs,
          );
        }
      },
    );

    sendToHaskell("get_extensions");
    sendToHaskell("get_instruction_set");
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

    let sawError = false;
    for (let i = this.systemLogShown; i < log.length; i++) {
      const ev = log[i];
      const level = severityToLevel(ev.severity);
      const msg = formatSystemEvent(ev);
      const id = logStore.log(level, systemEventTag(ev), msg);
      if (ev.notice?.kind === "Syscall")
        this.syscallEntries.set(i, { id, msg });
      if (level === "error") sawError = true;
    }
    if (log.length > this.systemLogShown) this.systemLogShown = log.length;

    for (const [i, entry] of this.syscallEntries) {
      const ev = log[i];
      if (ev?.notice?.kind !== "Syscall") continue;
      const msg = formatSystemEvent(ev);
      if (msg !== entry.msg) {
        logStore.update(entry.id, msg);
        entry.msg = msg;
      }
    }

    if (sawError) terminalStore.autoSwitch("system");
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
    const buildFiles = buildStore.resolveBuildFiles();
    const entryFile = buildFiles[0];
    if (!entryFile) {
      logStore.log("error", "BUILD", "No file open to compile.");
      return;
    }
    // The emulator narrates the build itself (the "assembled N ... entry" line,
    // plus any faults); we just surface the system console on user action.
    terminalStore.autoSwitch("system");
    this.compileError = null;
    const pool = fileStore.openFiles.map((f) => ({
      name: f.name,
      content: f.content,
    }));
    const entry = buildFiles.map((f) => f.name);
    this.pendingSnapshot = {
      fileId: entryFile.id,
      content: entryFile.content,
      files: pool,
      entry,
    };
    sendToHaskell("load", { files: pool, entry });
  }

  public handleRun() {
    if (terminalStore.clearOnRun) terminalStore.program.clear();
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
