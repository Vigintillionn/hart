<script lang="ts">
  import { terminalStore } from "$lib/terminalStore.svelte.js";
  import { cpuStore } from "$lib/cpuStore.svelte.js";
  import Terminal from "./Terminal.svelte";
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

{#snippet terminalPane(
  id: string,
  outputBuffer: string,
  waitingForInput: boolean,
  onSubmitInput?: (text: string) => void,
  hideCursor: boolean = false,
)}
  <div
    class="absolute inset-0 z-10 {terminalStore.activeTab === id
      ? 'visible'
      : 'invisible'}"
  >
    <Terminal {outputBuffer} {waitingForInput} {onSubmitInput} {hideCursor} />
  </div>
{/snippet}

<div class="flex flex-col h-full">
  <div class="flex gap-px bg-zinc-950 border-b border-zinc-800">
    {@render tab("system", "Assembler Output")}
    {#if cpuStore.cpuState}
      {@render tab("program", "Program Console")}
    {/if}
  </div>

  <div class="flex-1 relative overflow-hidden bg-zinc-950">
    {@render terminalPane(
      "system",
      terminalStore.system.logs.join("\n"),
      false,
      undefined,
      true
    )}

    {#if cpuStore.cpuState}
      {@render terminalPane(
        "program",
        terminalStore.program.logs.join("\n"),
        cpuStore.cpuState.status === "WaitingForInput",
        (text) => cpuStore.submitInput(text),
      )}
    {/if}
  </div>
</div>
