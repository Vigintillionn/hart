<script lang="ts">
  import { cpuStore } from "$lib/cpuStore.svelte";
  import CpuHeader from "./CpuHeader.svelte";
  import RegisterFile from "./RegisterFile.svelte";
  import MemoryView from "./MemoryView.svelte";
</script>

<div class="flex flex-col h-full overflow-hidden">
  <div class="bg-zinc-950 px-3 py-1.5 text-xs uppercase tracking-wider text-zinc-500 border-b border-zinc-800 shrink-0">
    CPU State
  </div>
  
  {#if cpuStore.cpuState}
    <div class="flex-1 overflow-y-auto p-4 min-h-[30%]">
      <CpuHeader pc={cpuStore.cpuState.pc} cycles={cpuStore.cpuState.cycles} />
      <RegisterFile registers={cpuStore.cpuState.regs} />
    </div>

    <div class="h-1/2 border-t border-zinc-800 flex flex-col shrink-0">
      <MemoryView mem={cpuStore.cpuState.mem} />
    </div>
  {:else}
    <div class="flex items-center justify-center h-32 text-zinc-600 italic text-sm flex-1">
      Awaiting compilation...
    </div>
  {/if}
</div>
