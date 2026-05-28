<script lang="ts">
  import { onMount } from "svelte";
  import { listen } from "@tauri-apps/api/event";
  import { open, save } from "@tauri-apps/plugin-dialog";
  import { readTextFile, writeTextFile } from "@tauri-apps/plugin-fs";
  import Editor from "../components/Editor.svelte";
  import type { CpuState } from "../bindings/CpuState";
  import type { EmulatorResponse } from "../bindings/EmulatorResponse";
  import Header from "../components/Header.svelte";
  import type {
    CpuHandlers,
    FileHandlers,
    OpenFile,
    SourceMap,
  } from "$lib/types";
  import { sendToHaskell } from "$lib/util";
  import StyleSettings from "../components/StyleSettings.svelte";
  import CpuHeader from "../components/CpuHeader.svelte";
  import RegisterFile from "../components/RegisterFile.svelte";
  import TerminalContainer from "../components/TerminalContainer.svelte";
  import { terminalStore } from "$lib/terminalStore.svelte";

  let showSettings = $state(false);
  let cpuState = $state<CpuState | null>(null);
  let sourceMap = $state<SourceMap>([]);

  let openFiles = $state<OpenFile[]>([
    {
      id: "default",
      name: "untitled.s",
      path: null,
      content: ".text\nmain:\n  li a0, 5\n  li a7, 93\n  ecall",
    },
  ]);
  let activeFileId = $state("default");
  let activeFile = $derived(
    openFiles.find((f) => f.id === activeFileId) || openFiles[0],
  );

  onMount(() => {
    let unlisten: (() => void) | undefined;

    listen<EmulatorResponse>("emulator-update", (event) => {
      const response = event.payload;

      if (response.type === "state") {
        cpuState = response.data;
        if ((cpuState as any).outputBuffer) {
          terminalStore.program.set((cpuState as any).outputBuffer);
        } else {
          terminalStore.program.clear();
        }
      } else if (response.type === "loaded") {
        cpuState = response.state;
        sourceMap = response.sourceMap;
        terminalStore.system.log(`[SUCCESS]: Program loaded successfully.`);
        terminalStore.setActiveTab("program");
      } else if (response.type === "error") {
        terminalStore.system.log(`[ERROR]: ${response.message}`);
        terminalStore.setActiveTab("system");
      } else if (response.type === "need_input") {
        if (cpuState) {
          cpuState.status = "WaitingForInput";
        }
        terminalStore.setActiveTab("program");
      }
    }).then((fn) => {
      unlisten = fn;
    });

    return () => {
      if (unlisten) unlisten();
    };
  });

  const cpuHandlers: CpuHandlers = {
    handleLoadProgram: () => {
      terminalStore.setActiveTab("system");
      terminalStore.system.log("> Compiling program...");
      sendToHaskell("load", activeFile.content);
    },
    handleRun: () => sendToHaskell("run"),
    handleStepFwd: () => sendToHaskell("step_forward"),
    handleStepBack: () => sendToHaskell("step_back"),
    handleRewind: () => sendToHaskell("rewind"),
    submitInput: (text: string) => sendToHaskell("input", text),
  };

  const fileHandlers: FileHandlers = {
    handleOpenFile: async () => {
      const selected = await open({
        multiple: false,
        filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
      });

      if (selected && typeof selected === "string") {
        const content = await readTextFile(selected);
        const name = selected.split(/[\/\\]/).pop() || "untitled.s";
        const id = Date.now().toString();

        openFiles.push({ id, name, path: selected, content });
        activeFileId = id;
      }
    },
    handleSaveFile: async () => {
      if (!activeFile) return;

      if (activeFile.path) {
        await writeTextFile(activeFile.path, activeFile.content);
      } else {
        const selected = await save({
          filters: [{ name: "Assembly", extensions: ["s", "asm"] }],
        });
        if (selected) {
          await writeTextFile(selected, activeFile.content);
          activeFile.path = selected;
          activeFile.name = selected.split(/[\/\\]/).pop() || activeFile.name;
        }
      }
    },
    closeFile: (id: string, e: Event) => {
      e.stopPropagation();
      if (openFiles.length === 1) return; // don't close last file

      const idx = openFiles.findIndex((f) => f.id === id);
      if (idx > -1) {
        openFiles.splice(idx, 1);
        if (activeFileId === id) {
          activeFileId = openFiles[Math.max(0, idx - 1)].id;
        }
      }
    },
  };
</script>

<div
  class="flex flex-col h-screen w-screen relative bg-zinc-950 text-zinc-300 font-sans overflow-hidden"
>
  <Header {fileHandlers} {cpuHandlers} {cpuState} {showSettings} />
  {#if showSettings}
    <StyleSettings {showSettings} />
  {/if}

  <main class="flex flex-1 overflow-hidden">
    <section
      class="flex flex-col flex-2 min-w-0 bg-zinc-900 border-r border-zinc-800"
    >
      <Editor
        {openFiles}
        setActiveFile={(id: string) => (activeFileId = id)}
        pc={cpuState?.pc ?? 0}
        {sourceMap}
        {fileHandlers}
        {activeFileId}
      />
    </section>

    <!-- Debugger Pane -->
    <aside class="flex flex-col flex-1 min-w-75 bg-zinc-900">
      <div
        class="bg-zinc-950 px-3 py-1.5 text-xs uppercase tracking-wider text-zinc-500 border-b border-zinc-800"
      >
        CPU State
      </div>
      <div class="p-4 overflow-y-auto">
        {#if cpuState}
          <CpuHeader pc={cpuState.pc} cycles={cpuState.cycles} />
          <RegisterFile registers={cpuState.regs} />
        {:else}
          <div
            class="flex items-center justify-center h-32 text-zinc-600 italic text-sm"
          >
            Awaiting compilation...
          </div>
        {/if}
      </div>
    </aside>
  </main>

  <footer
    class="flex flex-col h-[30%] min-h-50 bg-zinc-900 border-t border-zinc-800"
  >
    <TerminalContainer {cpuState} submitInput={cpuHandlers.submitInput} />
  </footer>
</div>
