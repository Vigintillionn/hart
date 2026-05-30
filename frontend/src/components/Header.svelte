<script lang="ts">
  import { fileStore } from "$lib/fileStore.svelte";
  import { cpuStore } from "$lib/cpuStore.svelte";
  import { layoutStore } from "$lib/layoutStore.svelte";

  interface Props {
    showSettings: boolean;
  }

  let { showSettings = $bindable() }: Props = $props();
</script>

<header
  class="flex items-center justify-between px-4 py-2 bg-zinc-900 border-b border-zinc-950 shadow-sm z-10"
>
  <div class="font-semibold text-white text-lg tracking-wide">
    RISC-V Studio
  </div>
  <div class="flex gap-2 items-center">
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={() => fileStore.handleOpenFile()}>Open File</button
    >
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={() => fileStore.handleSaveFile()}>Save</button
    >
    <div class="w-px h-6 bg-zinc-700 mx-1"></div>
    <button
      class="px-4 py-1.5 bg-sky-600 hover:bg-sky-500 text-sm font-medium text-white rounded shadow-sm transition-colors duration-200 border-none cursor-pointer"
      onclick={() => cpuStore.handleLoadProgram()}>Load & Compile</button
    >
    <div class="w-px h-6 bg-zinc-700 mx-1"></div>
    <div class="relative group">
      <button class="px-3 py-1.5 bg-zinc-800 group-hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer flex items-center gap-1">
        👁 View ▼
      </button>
      <div class="absolute right-0 top-full hidden group-hover:block w-48 z-50 pt-1">
        <div class="bg-zinc-800 border border-zinc-700 rounded shadow-xl overflow-hidden py-1">
          <button class="w-full text-left px-4 py-2 hover:bg-zinc-700 text-sm text-zinc-300 border-none cursor-pointer bg-transparent transition-colors flex items-center gap-2" onclick={() => layoutStore.toggleCpu(!layoutStore.isCpuVisible)}>
            <span class="w-4 inline-flex justify-center text-sky-400 font-bold">{layoutStore.isCpuVisible ? '✓' : ''}</span> CPU Panel
          </button>
          
          {#if layoutStore.isCpuVisible}
            <div class="pl-6 border-l-2 border-zinc-700 ml-4 my-1">
              <button class="w-full text-left px-4 py-1.5 hover:bg-zinc-700 text-xs text-zinc-400 border-none cursor-pointer bg-transparent transition-colors flex items-center gap-2" onclick={() => layoutStore.toggleRegisters(!layoutStore.isRegistersVisible)}>
                <span class="w-3 inline-flex justify-center text-sky-400 font-bold">{layoutStore.isRegistersVisible ? '✓' : ''}</span> Registers
              </button>
              <button class="w-full text-left px-4 py-1.5 hover:bg-zinc-700 text-xs text-zinc-400 border-none cursor-pointer bg-transparent transition-colors flex items-center gap-2" onclick={() => layoutStore.toggleMemory(!layoutStore.isMemoryVisible)}>
                <span class="w-3 inline-flex justify-center text-sky-400 font-bold">{layoutStore.isMemoryVisible ? '✓' : ''}</span> Memory
              </button>
            </div>
          {/if}

          <button class="w-full text-left px-4 py-2 hover:bg-zinc-700 text-sm text-zinc-300 border-none cursor-pointer bg-transparent transition-colors flex items-center gap-2" onclick={() => layoutStore.toggleTerminal(!layoutStore.isTerminalVisible)}>
            <span class="w-4 inline-flex justify-center text-sky-400 font-bold">{layoutStore.isTerminalVisible ? '✓' : ''}</span> Terminal
          </button>
          <hr class="border-zinc-700 my-1" />
          <button class="w-full text-left px-4 py-2 hover:bg-zinc-700 text-sm text-zinc-400 border-none cursor-pointer bg-transparent transition-colors flex items-center gap-2" onclick={() => layoutStore.resetLayout()}>
            <span class="w-4 inline-flex justify-center">↻</span> Reset Layout
          </button>
        </div>
      </div>
    </div>
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={() => (showSettings = !showSettings)}>🎨 Theme</button
    >
    <div class="w-px h-6 bg-zinc-700 mx-1"></div>
    {#if cpuStore.cpuState?.status === 'Running'}
      <button
        class="px-3 py-1.5 bg-amber-700 hover:bg-amber-600 text-sm font-medium text-white rounded shadow-sm transition-colors duration-200 border-none cursor-pointer"
        onclick={() => cpuStore.handlePause()}>Pause</button
      >
    {:else}
      <button
        class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
        onclick={() => cpuStore.handleRun()}
        disabled={!cpuStore.cpuState}>Run</button
      >
    {/if}
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={() => cpuStore.handleStepFwd()}
      disabled={!cpuStore.cpuState}>Step ➡</button
    >
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={() => cpuStore.handleStepBack()}
      disabled={!cpuStore.cpuState}>⬅ Step</button
    >
    <button
      class="px-3 py-1.5 bg-red-900 hover:bg-red-800 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 shadow-sm border-none cursor-pointer"
      onclick={() => cpuStore.handleRewind()}
      disabled={!cpuStore.cpuState}>Rewind</button
    >
  </div>
  <div class="flex items-center">
    {#if cpuStore.cpuState}
      <span
        class="px-3 py-1 rounded-full text-xs font-bold tracking-wide {cpuStore.cpuState.status ===
        'Running'
          ? 'bg-green-900 text-green-300'
          : cpuStore.cpuState.status === 'Halted'
            ? 'bg-red-950 text-red-300'
            : cpuStore.cpuState.status === 'WaitingForInput'
              ? 'bg-amber-900 text-amber-200'
              : 'bg-zinc-800 text-zinc-400'}">{cpuStore.cpuState.status}</span
      >
    {:else}
      <span
        class="px-3 py-1 rounded-full text-xs font-bold tracking-wide bg-zinc-800 text-zinc-400"
        >Idle</span
      >
    {/if}
  </div>
</header>
