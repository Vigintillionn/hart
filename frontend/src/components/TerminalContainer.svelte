<script lang="ts">
  import { terminalStore } from "$lib/terminalStore.svelte.js";
  import type { CpuState } from "../bindings/CpuState";
  import Terminal from "./Terminal.svelte";

  interface Props {
    cpuState: CpuState | null;
    submitInput: (input: string) => void;
  }

  let { cpuState, submitInput } = $props();
</script>

{#snippet tab(id: string, label: string)}
  <button
    class="px-4 py-1.5 cursor-pointer text-xs uppercase tracking-wider border-none outline-none {terminalStore.activeTab ===
    id
      ? 'bg-zinc-900 text-white border-t border-t-sky-500'
      : 'bg-zinc-950 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900'}"
    onclick={() => (terminalStore.activeTab = id)}
  >
    {label}
  </button>
{/snippet}

<div class="flex flex-col h-full">
  <div class="flex gap-px bg-zinc-950 border-b border-zinc-800">
    {@render tab("system", "Assembler Output")}
    {#if cpuState}
      {@render tab("program", "Program Console")}
    {/if}
  </div>

  <div class="flex-1 relative overflow-hidden bg-zinc-950">
    <div
      class="absolute inset-0 z-10 {terminalStore.activeTab === 'system'
        ? 'visible'
        : 'invisible'}"
    >
      <Terminal
        outputBuffer={terminalStore.system.logs.join("\n")}
        waitingForInput={false}
      />
    </div>

    {#if cpuState}
      <div
        class="absolute inset-0 z-10 {terminalStore.activeTab === 'program'
          ? 'visible'
          : 'invisible'}"
      >
        <Terminal
          outputBuffer={terminalStore.program.logs.join("\n")}
          waitingForInput={cpuState.status === "WaitingForInput"}
          onSubmitInput={submitInput}
        />
      </div>
    {/if}
  </div>
</div>
