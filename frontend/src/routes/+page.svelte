<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen } from "@tauri-apps/api/event";
  import Editor from "../components/Editor.svelte";
  import type { CpuState } from "../bindings/CpuState";
  import type { EmulatorResponse } from "../bindings/EmulatorResponse";

  let cpuState = $state<CpuState | null>(null);
  let sourceCode = $state(".text\nmain:\n  li a0, 5\n  li a7, 93\n  ecall");
  let consoleOutput = $state("Welcome to RISC-V Studio.\nType your assembly and click 'Load & Compile'.\n");
  let userInput = $state("");

  async function sendToHaskell(command: string, data?: string) {
    const payload = data ? { command, data } : { command };
    await invoke("send_command", { cmd: JSON.stringify(payload) });
  }

  onMount(async () => {
    await listen<EmulatorResponse>("emulator-update", (event) => {
      const response = event.payload;

      if (response.type === "state") {
        cpuState = response.data;
        if (cpuState.outputBuffer) {
          consoleOutput += cpuState.outputBuffer;
          scrollToBottom();
        }
      } else if (response.type === "error") {
        consoleOutput += `\n[ERROR]: ${response.message}\n`;
        scrollToBottom();
      }
    });
  });

  const handleLoad = () => {
    consoleOutput += "\n> Compiling program...\n";
    sendToHaskell("load", sourceCode);
  };
  const handleRun = () => sendToHaskell("run");
  const handleStepFwd = () => sendToHaskell("step_forward");
  const handleStepBack = () => sendToHaskell("step_back");
  const handleRewind = () => sendToHaskell("rewind");

  const submitInput = () => {
    consoleOutput += `${userInput}\n`;
    sendToHaskell("input", userInput);
    userInput = "";
  };

  let terminalDiv: HTMLTextAreaElement;
  const scrollToBottom = () => {
    setTimeout(() => {
      if (terminalDiv) terminalDiv.scrollTop = terminalDiv.scrollHeight;
    }, 10);
  };

  const toHex = (num: number) => "0x" + (num >>> 0).toString(16).padStart(8, '0');
</script>

<div class="ide-layout">
  <header class="toolbar">
    <div class="branding">RISC-V Studio</div>
    <div class="controls">
      <button class="btn primary" onclick={handleLoad}>Load & Compile</button>
      <div class="divider"></div>
      <button class="btn" onclick={handleRun} disabled={!cpuState}>Run</button>
      <button class="btn" onclick={handleStepFwd} disabled={!cpuState}>Step ➡</button>
      <button class="btn" onclick={handleStepBack} disabled={!cpuState}>⬅ Step</button>
      <button class="btn danger" onclick={handleRewind} disabled={!cpuState}>Rewind</button>
    </div>
    <div class="status-indicator">
      {#if cpuState}
        <span class="badge {cpuState.status.toLowerCase()}">{cpuState.status}</span>
      {:else}
        <span class="badge idle">Idle</span>
      {/if}
    </div>
  </header>

  <main class="workspace">
    
    <section class="pane editor-pane">
      <div class="pane-header">Source Code</div>
      <div class="editor-wrapper">
        <Editor 
          bind:code={sourceCode} 
          currentPc={cpuState?.pc ?? 0}
          sourceMap={cpuState?.sourceMap ?? []} 
        />
      </div>
    </section>

    <aside class="pane debugger-pane">
      <div class="pane-header">CPU State</div>
      <div class="debugger-content">
        {#if cpuState}
          <div class="cpu-metrics">
            <div class="metric"><span>PC</span> <strong>{cpuState.pc}</strong></div>
            <div class="metric"><span>Cycles</span> <strong>{cpuState.cycles}</strong></div>
          </div>

          <div class="registers-grid">
            {#each cpuState.regs as reg, i}
              <div class="reg-cell">
                <span class="reg-name">x{i}</span>
                <span class="reg-value" title={reg.toString()}>{toHex(reg)}</span>
              </div>
            {/each}
          </div>
        {:else}
          <div class="empty-state">
            Awaiting compilation...
          </div>
        {/if}
      </div>
    </aside>

  </main>

  <footer class="pane terminal-pane">
    <div class="pane-header">Terminal / I/O</div>
    <textarea 
      bind:this={terminalDiv}
      class="terminal-output" 
      readonly 
      value={consoleOutput}
    ></textarea>
    
    {#if cpuState?.status === "AwaitingInput"}
      <div class="input-prompt">
        <span class="prompt-arrow">❯</span>
        <input 
          type="text" 
          bind:value={userInput} 
          placeholder="Program is waiting for input..."
          onkeydown={(e) => e.key === 'Enter' && submitInput()} 
          autofocus
        />
      </div>
    {/if}
  </footer>
</div>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    background-color: #1e1e1e;
    color: #cccccc;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    overflow: hidden; 
  }

  .ide-layout {
    display: flex;
    flex-direction: column;
    height: 100vh;
    width: 100vw;
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

  .btn:hover:not(:disabled) { background-color: #555; }
  .btn:disabled { color: #777; cursor: not-allowed; }
  
  .btn.primary { background-color: #0e639c; }
  .btn.primary:hover { background-color: #1177bb; }
  
  .btn.danger { background-color: #8a2a2a; }
  .btn.danger:hover { background-color: #a03030; }

  .badge {
    padding: 4px 8px;
    border-radius: 12px;
    font-size: 0.8rem;
    font-weight: bold;
  }
  .badge.running { background: #1b5e20; color: #a5d6a7; }
  .badge.halted { background: #b71c1c; color: #ffcdd2; }
  .badge.awaitinginput { background: #f57f17; color: #fff9c4; }
  .badge.idle { background: #424242; color: #bdbdbd; }

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

  .metric span { font-size: 0.8rem; color: #888; }
  .metric strong { font-size: 1.2rem; color: #dcdcaa; font-family: monospace; }

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

  .reg-name { color: #569cd6; font-weight: bold; }
  .reg-value { color: #ce9178; }

  .terminal-pane {
    height: 25%;
    min-height: 150px;
    border-top: none;
  }

  .terminal-output {
    flex: 1;
    background-color: #1e1e1e;
    color: #4af626;
    border: none;
    padding: 12px;
    font-family: "Courier New", Courier, monospace;
    font-size: 0.95rem;
    resize: none;
    outline: none;
  }

  .input-prompt {
    display: flex;
    background-color: #000;
    padding: 8px 12px;
    align-items: center;
  }

  .prompt-arrow {
    color: #f57f17;
    margin-right: 12px;
    font-weight: bold;
  }

  .input-prompt input {
    flex: 1;
    background: transparent;
    border: none;
    color: #fff;
    font-family: monospace;
    font-size: 1rem;
    outline: none;
  }
</style>
