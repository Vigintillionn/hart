<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen } from "@tauri-apps/api/event";
  import { open, save } from "@tauri-apps/plugin-dialog";
  import { readTextFile, writeTextFile } from "@tauri-apps/plugin-fs";
  import Editor from "../components/Editor.svelte";
  import Terminal from "../components/Terminal.svelte";
  import { themeColors } from "../lib/theme.svelte";
  import type { CpuState } from "../bindings/CpuState";
  import type { EmulatorResponse } from "../bindings/EmulatorResponse";

  let showSettings = $state(false);
  let cpuState = $state<CpuState | null>(null);
  let sourceMap = $state<[number, number][]>([]);

  type OpenFile = {
    id: string;
    name: string;
    path: string | null;
    content: string;
  };

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

  let activeTerminalTab = $state<"system" | "program">("system");
  let systemOutput = $state(
    "Welcome to RISC-V Studio.\nType your assembly and click 'Load & Compile'.\n",
  );
  let programOutput = $state("");

  async function sendToHaskell(command: string, data?: string) {
    const payload = data ? { command, data } : { command };
    await invoke("send_command", { cmd: JSON.stringify(payload) });
  }

  onMount(async () => {
    await listen<EmulatorResponse>("emulator-update", (event) => {
      const response = event.payload;

      if (response.type === "state") {
        cpuState = response.data;
        if ((cpuState as any).outputBuffer) {
          programOutput = (cpuState as any).outputBuffer;
        } else {
          programOutput = "";
        }
      } else if (response.type === "loaded") {
        cpuState = response.state;
        sourceMap = response.sourceMap;
        systemOutput += `\n[SUCCESS]: Program loaded successfully.\n`;
        activeTerminalTab = "program";
      } else if (response.type === "error") {
        systemOutput += `\n[ERROR]: ${response.message}\n`;
        activeTerminalTab = "system";
      } else if (response.type === "need_input") {
        if (cpuState) {
          cpuState.status = "WaitingForInput";
        }
        activeTerminalTab = "program";
      }
    });
  });

  const handleLoad = () => {
    systemOutput += "\n> Compiling program...\n";
    sendToHaskell("load", activeFile.content);
  };

  const handleEditorChange = (id: string, content: string) => {
    const file = openFiles.find((f) => f.id === id);
    if (file) {
      file.content = content;
    }
  };

  const handleOpenFile = async () => {
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
  };

  const handleSaveFile = async () => {
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
  };

  const closeFile = (id: string, e: Event) => {
    e.stopPropagation();
    if (openFiles.length === 1) return; // don't close last file

    const idx = openFiles.findIndex((f) => f.id === id);
    if (idx > -1) {
      openFiles.splice(idx, 1);
      if (activeFileId === id) {
        activeFileId = openFiles[Math.max(0, idx - 1)].id;
      }
    }
  };

  const handleRun = () => sendToHaskell("run");
  const handleStepFwd = () => sendToHaskell("step_forward");
  const handleStepBack = () => sendToHaskell("step_back");
  const handleRewind = () => sendToHaskell("rewind");

  const submitInput = (text: string) => {
    sendToHaskell("input", text);
  };

  const toHex = (num: number) =>
    "0x" + (num >>> 0).toString(16).padStart(8, "0");
</script>

<div
  class="flex flex-col h-screen w-screen relative bg-zinc-950 text-zinc-300 font-sans overflow-hidden"
>
  <header
    class="flex items-center justify-between px-4 py-2 bg-zinc-900 border-b border-zinc-950 shadow-sm z-10"
  >
    <div class="font-semibold text-white text-lg tracking-wide">
      RISC-V Studio
    </div>
    <div class="flex gap-2 items-center">
      <button
        class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
        onclick={handleOpenFile}>Open File</button
      >
      <button
        class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
        onclick={handleSaveFile}>Save</button
      >
      <div class="w-px h-6 bg-zinc-700 mx-1"></div>
      <button
        class="px-4 py-1.5 bg-sky-600 hover:bg-sky-500 text-sm font-medium text-white rounded shadow-sm transition-colors duration-200 border-none cursor-pointer"
        onclick={handleLoad}>Load & Compile</button
      >
      <div class="w-px h-6 bg-zinc-700 mx-1"></div>
      <button
        class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
        onclick={() => (showSettings = !showSettings)}>🎨 Theme</button
      >
      <div class="w-px h-6 bg-zinc-700 mx-1"></div>
      <button
        class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
        onclick={handleRun}
        disabled={!cpuState}>Run</button
      >
      <button
        class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
        onclick={handleStepFwd}
        disabled={!cpuState}>Step ➡</button
      >
      <button
        class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
        onclick={handleStepBack}
        disabled={!cpuState}>⬅ Step</button
      >
      <button
        class="px-3 py-1.5 bg-red-900 hover:bg-red-800 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 shadow-sm border-none cursor-pointer"
        onclick={handleRewind}
        disabled={!cpuState}>Rewind</button
      >
    </div>
    <div class="flex items-center">
      {#if cpuState}
        <span
          class="px-3 py-1 rounded-full text-xs font-bold tracking-wide {cpuState.status ===
          'Running'
            ? 'bg-green-900 text-green-300'
            : cpuState.status === 'Halted'
              ? 'bg-red-950 text-red-300'
              : cpuState.status === 'WaitingForInput'
                ? 'bg-amber-900 text-amber-200'
                : 'bg-zinc-800 text-zinc-400'}">{cpuState.status}</span
        >
      {:else}
        <span
          class="px-3 py-1 rounded-full text-xs font-bold tracking-wide bg-zinc-800 text-zinc-400"
          >Idle</span
        >
      {/if}
    </div>
  </header>

  {#if showSettings}
    <div
      class="absolute top-15 right-5 w-72 bg-zinc-900 border border-zinc-800 rounded-lg shadow-xl z-50 flex flex-col overflow-hidden"
    >
      <div
        class="flex justify-between items-center px-4 py-3 bg-zinc-950 border-b border-zinc-800"
      >
        <h3 class="m-0 text-sm font-semibold text-white">Theme Colors</h3>
        <button
          class="bg-transparent border-none text-zinc-400 hover:text-white text-xl leading-none cursor-pointer p-0 m-0"
          onclick={() => (showSettings = false)}>×</button
        >
      </div>
      <div class="flex flex-col gap-3 p-4">
        <label class="flex justify-between items-center text-zinc-300 text-sm">
          <span>Background</span>
          <input
            type="color"
            class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
            bind:value={themeColors.background}
          />
        </label>
        <label class="flex justify-between items-center text-zinc-300 text-sm">
          <span>Keywords (li, add)</span>
          <input
            type="color"
            class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
            bind:value={themeColors.keyword}
          />
        </label>
        <label class="flex justify-between items-center text-zinc-300 text-sm">
          <span>Registers (x0, a0)</span>
          <input
            type="color"
            class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
            bind:value={themeColors.register}
          />
        </label>
        <label class="flex justify-between items-center text-zinc-300 text-sm">
          <span>Directives (.text)</span>
          <input
            type="color"
            class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
            bind:value={themeColors.directive}
          />
        </label>
        <label class="flex justify-between items-center text-zinc-300 text-sm">
          <span>Numbers (100, 0x10)</span>
          <input
            type="color"
            class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
            bind:value={themeColors.number}
          />
        </label>
        <label class="flex justify-between items-center text-zinc-300 text-sm">
          <span>Strings ("...")</span>
          <input
            type="color"
            class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
            bind:value={themeColors.string}
          />
        </label>
        <label class="flex justify-between items-center text-zinc-300 text-sm">
          <span>Comments (#)</span>
          <input
            type="color"
            class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
            bind:value={themeColors.comment}
          />
        </label>
      </div>
    </div>
  {/if}

  <main class="flex flex-1 overflow-hidden">
    <!-- Editor Pane -->
    <section
      class="flex flex-col flex-2 min-w-0 bg-zinc-900 border-r border-zinc-800"
    >
      <div class="flex bg-zinc-950 border-b border-zinc-800">
        {#each openFiles as file}
          <!-- svelte-ignore a11y_click_events_have_key_events -->
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="flex items-center gap-2 px-4 py-2 cursor-pointer text-sm border-r border-zinc-800 select-none {activeFileId ===
            file.id
              ? 'bg-zinc-900 text-white border-t-2 border-t-sky-500'
              : 'bg-zinc-950 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900'}"
            onclick={() => (activeFileId = file.id)}
          >
            {file.name}
            {#if openFiles.length > 1}
              <button
                class="bg-transparent border-none text-zinc-500 hover:text-red-500 text-lg leading-none cursor-pointer p-0 m-0"
                onclick={(e) => closeFile(file.id, e)}>×</button
              >
            {/if}
          </div>
        {/each}
      </div>
      <div class="flex-1 relative overflow-hidden">
        <Editor
          {activeFileId}
          files={openFiles}
          onContentChange={handleEditorChange}
          currentPc={cpuState?.pc ?? 0}
          {sourceMap}
        />
      </div>
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
          <div
            class="flex justify-between bg-zinc-950 p-3 rounded-lg border border-zinc-800 mb-4 shadow-inner"
          >
            <div class="flex flex-col">
              <span class="text-xs text-zinc-500 uppercase tracking-wide"
                >PC</span
              >
              <strong class="text-lg text-amber-200 font-mono"
                >{cpuState.pc}</strong
              >
            </div>
            <div class="flex flex-col text-right">
              <span class="text-xs text-zinc-500 uppercase tracking-wide"
                >Cycles</span
              >
              <strong class="text-lg text-amber-200 font-mono"
                >{cpuState.cycles}</strong
              >
            </div>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-2">
            {#each cpuState.regs as reg, i}
              <div
                class="flex justify-between items-center bg-zinc-950 px-2 py-1.5 rounded border border-zinc-800 font-mono shadow-sm"
              >
                <span class="text-sky-400 font-bold text-sm">x{i}</span>
                <span class="text-orange-300 text-sm" title={reg.toString()}
                  >{toHex(reg)}</span
                >
              </div>
            {/each}
          </div>
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
    <div class="flex gap-px bg-zinc-950 border-b border-zinc-800">
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="px-4 py-1.5 cursor-pointer text-xs uppercase tracking-wider {activeTerminalTab ===
        'system'
          ? 'bg-zinc-900 text-white border-t border-t-sky-500'
          : 'bg-zinc-950 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900'}"
        onclick={() => (activeTerminalTab = "system")}
      >
        Assembler Output
      </div>
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="px-4 py-1.5 cursor-pointer text-xs uppercase tracking-wider {activeTerminalTab ===
        'program'
          ? 'bg-zinc-900 text-white border-t border-t-sky-500'
          : 'bg-zinc-950 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900'}"
        onclick={() => (activeTerminalTab = "program")}
      >
        Program Console
      </div>
    </div>

    <div class="flex-1 relative overflow-hidden bg-zinc-950">
      <div
        class="absolute inset-0 z-10 {activeTerminalTab === 'system'
          ? 'visible'
          : 'invisible'}"
      >
        <Terminal outputBuffer={systemOutput} waitingForInput={false} />
      </div>
      <div
        class="absolute inset-0 z-10 {activeTerminalTab === 'program'
          ? 'visible'
          : 'invisible'}"
      >
        <Terminal
          outputBuffer={programOutput}
          waitingForInput={cpuState?.status === "WaitingForInput"}
          onSubmitInput={submitInput}
        />
      </div>
    </div>
  </footer>
</div>
