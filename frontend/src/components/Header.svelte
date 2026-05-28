<script lang="ts">
  import type { CpuHandlers, FileHandlers } from "$lib/types";
  import type { CpuState } from "../bindings/CpuState";

  interface Props {
    cpuHandlers: CpuHandlers;
    fileHandlers: FileHandlers;
    showSettings: boolean;
    cpuState: CpuState | null;
  }

  let { cpuHandlers, fileHandlers, showSettings, cpuState }: Props = $props();
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
      onclick={fileHandlers.handleOpenFile}>Open File</button
    >
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={fileHandlers.handleSaveFile}>Save</button
    >
    <div class="w-px h-6 bg-zinc-700 mx-1"></div>
    <button
      class="px-4 py-1.5 bg-sky-600 hover:bg-sky-500 text-sm font-medium text-white rounded shadow-sm transition-colors duration-200 border-none cursor-pointer"
      onclick={cpuHandlers.handleLoadProgram}>Load & Compile</button
    >
    <div class="w-px h-6 bg-zinc-700 mx-1"></div>
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={() => (showSettings = !showSettings)}>🎨 Theme</button
    >
    <div class="w-px h-6 bg-zinc-700 mx-1"></div>
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={cpuHandlers.handleRun}
      disabled={!cpuState}>Run</button
    >
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={cpuHandlers.handleStepFwd}
      disabled={!cpuState}>Step ➡</button
    >
    <button
      class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 border-none cursor-pointer"
      onclick={cpuHandlers.handleStepBack}
      disabled={!cpuState}>⬅ Step</button
    >
    <button
      class="px-3 py-1.5 bg-red-900 hover:bg-red-800 disabled:opacity-50 disabled:cursor-not-allowed text-sm text-white rounded transition-colors duration-200 shadow-sm border-none cursor-pointer"
      onclick={cpuHandlers.handleRewind}
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
