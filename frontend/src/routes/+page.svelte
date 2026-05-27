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

<div class="ide-layout">
  <header class="toolbar">
    <div class="branding">RISC-V Studio</div>
    <div class="controls">
      <button class="btn" onclick={handleOpenFile}>Open File</button>
      <button class="btn" onclick={handleSaveFile}>Save</button>
      <div class="divider"></div>
      <button class="btn primary" onclick={handleLoad}>Load & Compile</button>
      <div class="divider"></div>
      <button class="btn" onclick={() => (showSettings = !showSettings)}
        >🎨 Theme</button
      >
      <div class="divider"></div>
      <button class="btn" onclick={handleRun} disabled={!cpuState}>Run</button>
      <button class="btn" onclick={handleStepFwd} disabled={!cpuState}
        >Step ➡</button
      >
      <button class="btn" onclick={handleStepBack} disabled={!cpuState}
        >⬅ Step</button
      >
      <button class="btn danger" onclick={handleRewind} disabled={!cpuState}
        >Rewind</button
      >
    </div>
    <div class="status-indicator">
      {#if cpuState}
        <span class="badge {cpuState.status.toLowerCase()}"
          >{cpuState.status}</span
        >
      {:else}
        <span class="badge idle">Idle</span>
      {/if}
    </div>
  </header>

  {#if showSettings}
    <div class="settings-modal">
      <div class="settings-header">
        <h3>Theme Colors</h3>
        <button class="close-btn" onclick={() => (showSettings = false)}
          >×</button
        >
      </div>
      <div class="settings-body">
        <label>
          <span>Background</span>
          <input type="color" bind:value={themeColors.background} />
        </label>
        <label>
          <span>Keywords (li, add)</span>
          <input type="color" bind:value={themeColors.keyword} />
        </label>
        <label>
          <span>Registers (x0, a0)</span>
          <input type="color" bind:value={themeColors.register} />
        </label>
        <label>
          <span>Directives (.text)</span>
          <input type="color" bind:value={themeColors.directive} />
        </label>
        <label>
          <span>Numbers (100, 0x10)</span>
          <input type="color" bind:value={themeColors.number} />
        </label>
        <label>
          <span>Strings ("...")</span>
          <input type="color" bind:value={themeColors.string} />
        </label>
        <label>
          <span>Comments (#)</span>
          <input type="color" bind:value={themeColors.comment} />
        </label>
      </div>
    </div>
  {/if}

  <main class="workspace">
    <section class="pane editor-pane">
      <div class="editor-tabs">
        {#each openFiles as file}
          <!-- svelte-ignore a11y_click_events_have_key_events -->
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="tab {activeFileId === file.id ? 'active' : ''}"
            onclick={() => (activeFileId = file.id)}
          >
            {file.name}
            {#if openFiles.length > 1}
              <button class="close-tab" onclick={(e) => closeFile(file.id, e)}
                >×</button
              >
            {/if}
          </div>
        {/each}
      </div>
      <div class="editor-wrapper">
        <Editor
          {activeFileId}
          files={openFiles}
          onContentChange={handleEditorChange}
          currentPc={cpuState?.pc ?? 0}
          {sourceMap}
        />
      </div>
    </section>

    <aside class="pane debugger-pane">
      <div class="pane-header">CPU State</div>
      <div class="debugger-content">
        {#if cpuState}
          <div class="cpu-metrics">
            <div class="metric">
              <span>PC</span> <strong>{cpuState.pc}</strong>
            </div>
            <div class="metric">
              <span>Cycles</span> <strong>{cpuState.cycles}</strong>
            </div>
          </div>

          <div class="registers-grid">
            {#each cpuState.regs as reg, i}
              <div class="reg-cell">
                <span class="reg-name">x{i}</span>
                <span class="reg-value" title={reg.toString()}
                  >{toHex(reg)}</span
                >
              </div>
            {/each}
          </div>
        {:else}
          <div class="empty-state">Awaiting compilation...</div>
        {/if}
      </div>
    </aside>
  </main>

  <footer class="pane terminal-pane">
    <div class="terminal-tabs">
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="term-tab {activeTerminalTab === 'system' ? 'active' : ''}"
        onclick={() => (activeTerminalTab = "system")}
      >
        Assembler Output
      </div>
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="term-tab {activeTerminalTab === 'program' ? 'active' : ''}"
        onclick={() => (activeTerminalTab = "program")}
      >
        Program Console
      </div>
    </div>

    <div class="terminals-container">
      <div
        class="term-wrapper {activeTerminalTab === 'system'
          ? 'active'
          : 'hidden'}"
      >
        <Terminal outputBuffer={systemOutput} waitingForInput={false} />
      </div>
      <div
        class="term-wrapper {activeTerminalTab === 'program'
          ? 'active'
          : 'hidden'}"
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

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    background-color: #1e1e1e;
    color: #cccccc;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
      Helvetica, Arial, sans-serif;
    overflow: hidden;
  }

  .ide-layout {
    display: flex;
    flex-direction: column;
    height: 100vh;
    width: 100vw;
    position: relative;
  }

  .settings-modal {
    position: absolute;
    top: 50px;
    right: 20px;
    width: 300px;
    background: #252526;
    border: 1px solid #444;
    border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5);
    z-index: 1000;
    display: flex;
    flex-direction: column;
  }
  .settings-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    background: #2d2d2d;
    border-bottom: 1px solid #444;
    border-radius: 8px 8px 0 0;
  }
  .settings-header h3 {
    margin: 0;
    font-size: 1rem;
    color: #fff;
  }
  .close-btn {
    background: none;
    border: none;
    color: #aaa;
    font-size: 1.5rem;
    cursor: pointer;
    line-height: 1;
  }
  .close-btn:hover {
    color: #fff;
  }
  .settings-body {
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .settings-body label {
    display: flex;
    justify-content: space-between;
    align-items: center;
    color: #ccc;
    font-size: 0.9rem;
  }
  .settings-body input[type="color"] {
    background: none;
    border: 1px solid #444;
    border-radius: 4px;
    width: 30px;
    height: 30px;
    padding: 0;
    cursor: pointer;
  }

  .pane {
    display: flex;
    flex-direction: column;
    background-color: #252526;
    border: 1px solid #333;
  }

  .pane-header {
    background-color: #2d2d2d;
    padding: 4px 12px;
    font-size: 0.85rem;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: #969696;
    border-bottom: 1px solid #333;
  }

  .toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 16px;
    background-color: #333333;
    border-bottom: 1px solid #111;
  }

  .branding {
    font-weight: 600;
    color: #ffffff;
    font-size: 1.1rem;
  }

  .controls {
    display: flex;
    gap: 8px;
    align-items: center;
  }

  .divider {
    width: 1px;
    height: 24px;
    background-color: #555;
    margin: 0 8px;
  }

  .btn {
    background-color: #444;
    color: #fff;
    border: none;
    padding: 6px 12px;
    border-radius: 4px;
    font-size: 0.9rem;
    cursor: pointer;
    transition: background 0.2s;
  }

  .btn:hover:not(:disabled) {
    background-color: #555;
  }
  .btn:disabled {
    color: #777;
    cursor: not-allowed;
  }

  .btn.primary {
    background-color: #0e639c;
  }
  .btn.primary:hover {
    background-color: #1177bb;
  }

  .btn.danger {
    background-color: #8a2a2a;
  }
  .btn.danger:hover {
    background-color: #a03030;
  }

  .badge {
    padding: 4px 8px;
    border-radius: 12px;
    font-size: 0.8rem;
    font-weight: bold;
  }
  .badge.running {
    background: #1b5e20;
    color: #a5d6a7;
  }
  .badge.halted {
    background: #b71c1c;
    color: #ffcdd2;
  }
  .badge.waitingforinput {
    background: #f57f17;
    color: #fff9c4;
  }
  .badge.idle {
    background: #424242;
    color: #bdbdbd;
  }

  .workspace {
    display: flex;
    flex: 1;
    overflow: hidden;
  }

  .editor-pane {
    flex: 2;
    border-right: none;
    min-width: 0;
  }

  .editor-wrapper {
    flex: 1;
    overflow: hidden;
    position: relative;
  }

  .editor-tabs {
    display: flex;
    background-color: #2d2d2d;
    border-bottom: 1px solid #111;
  }
  .tab {
    padding: 8px 16px;
    background-color: #2d2d2d;
    color: #969696;
    cursor: pointer;
    font-size: 0.9rem;
    border-right: 1px solid #111;
    display: flex;
    align-items: center;
    gap: 8px;
    user-select: none;
  }
  .tab.active {
    background-color: #1e1e1e;
    color: #fff;
    border-top: 2px solid #0e639c;
  }
  .close-tab {
    background: none;
    border: none;
    color: inherit;
    cursor: pointer;
    font-size: 1.1rem;
    padding: 0;
    line-height: 1;
  }
  .close-tab:hover {
    color: #f44336;
  }

  .debugger-pane {
    flex: 1;
    min-width: 300px;
  }

  .debugger-content {
    padding: 12px;
    overflow-y: auto;
  }

  .cpu-metrics {
    display: flex;
    justify-content: space-between;
    background: #1e1e1e;
    padding: 12px;
    border-radius: 6px;
    margin-bottom: 16px;
    border: 1px solid #333;
  }

  .metric {
    display: flex;
    flex-direction: column;
  }

  .metric span {
    font-size: 0.8rem;
    color: #888;
  }
  .metric strong {
    font-size: 1.2rem;
    color: #dcdcaa;
    font-family: monospace;
  }

  .registers-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 8px;
  }

  .reg-cell {
    display: flex;
    justify-content: space-between;
    background: #1e1e1e;
    padding: 6px 10px;
    border-radius: 4px;
    border: 1px solid #333;
    font-family: monospace;
  }

  .reg-name {
    color: #569cd6;
    font-weight: bold;
  }
  .reg-value {
    color: #ce9178;
  }

  .terminal-pane {
    height: 30%;
    min-height: 200px;
    border-top: none;
    display: flex;
    flex-direction: column;
  }

  .terminal-tabs {
    display: flex;
    padding: 0;
    gap: 1px;
    background-color: #111;
  }
  .term-tab {
    padding: 6px 16px;
    background-color: #2d2d2d;
    color: #888;
    cursor: pointer;
    font-size: 0.85rem;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .term-tab.active {
    color: #fff;
    background-color: #1e1e1e;
    border-top: 1px solid #0e639c;
  }

  .terminals-container {
    flex: 1;
    position: relative;
    overflow: hidden;
  }
  .term-wrapper {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    visibility: hidden;
    z-index: 1;
  }
  .term-wrapper.active {
    visibility: visible;
    z-index: 2;
  }
</style>
