<script lang="ts">
  import { cpuStore } from "$lib/cpuStore.svelte";
  import { toHex } from "$lib/util";

  let pcShowHex = $state(true);

  const formatPc = (num: number) => (pcShowHex ? toHex(num) : num.toString());
</script>

<div
  class="bg-zinc-950 px-3 py-1.5 text-xs tracking-wider border-b border-zinc-800 shrink-0 flex items-baseline"
>
  <span class="text-zinc-500 uppercase">CPU State</span>
  {#if cpuStore.cpuState}
    <div class="ml-auto flex items-baseline gap-4">
      <div
        class="cursor-pointer flex items-baseline gap-1 w-28"
        onclick={() => (pcShowHex = !pcShowHex)}
        title="Click to toggle Hex/Dec"
      >
        <span class="text-zinc-500 shrink-0">PC:</span>
        <strong class="text-amber-200 font-mono">
          {formatPc(cpuStore.cpuState.pc || 0)}
        </strong>
      </div>

      <div class="flex items-baseline gap-1">
        <span class="text-zinc-500">Cycles:</span>
        <strong class="text-amber-200 font-mono">
          {cpuStore.cpuState.cycles || 0}
        </strong>
      </div>
    </div>
  {/if}
</div>
