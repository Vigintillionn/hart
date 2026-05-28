<script lang="ts">
  import { getRegName, toHex } from "$lib/util";
  import type { CpuState } from "../bindings/CpuState";

  interface Props {
    registers: CpuState["regs"];
  }

  let { registers }: Props = $props();

  let regsShowHex = $state(true);
  let showCanonicalNames = $state(false);

  let prevRegisters = $state<number[]>([]);
  let changedIndices = $state<Set<number>>(new Set());

  import { untrack } from "svelte";

  $effect(() => {
    const currentRegs = registers;
    untrack(() => {
      if (prevRegisters.length > 0) {
        const changed = new Set<number>();
        for (let i = 0; i < currentRegs.length; i++) {
          if (currentRegs[i] !== prevRegisters[i]) {
            changed.add(i);
          }
        }
        changedIndices = changed;
      }
      prevRegisters = [...currentRegs];
    });
  });

  const formatReg = (num: number) =>
    regsShowHex ? toHex(num) : num.toString();
</script>

<div class="flex justify-between items-center mb-2 px-1">
  <span class="text-xs text-zinc-500 uppercase tracking-wide">Registers</span>
  <div class="flex gap-1">
    <button
      class="px-2 py-0.5 text-[10px] uppercase font-bold rounded {regsShowHex
        ? 'bg-sky-900 text-sky-200'
        : 'bg-zinc-800 text-zinc-400 hover:bg-zinc-700'} border-none cursor-pointer transition-colors"
      onclick={() => (regsShowHex = true)}>Hex</button
    >
    <button
      class="px-2 py-0.5 text-[10px] uppercase font-bold rounded {!regsShowHex
        ? 'bg-sky-900 text-sky-200'
        : 'bg-zinc-800 text-zinc-400 hover:bg-zinc-700'} border-none cursor-pointer transition-colors"
      onclick={() => (regsShowHex = false)}>Dec</button
    >
  </div>
</div>

<div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-2">
  {#each registers as value, i}
    <div
      class="flex justify-between items-center px-2 py-1.5 rounded border font-mono shadow-sm transition-colors duration-300 {changedIndices.has(
        i,
      )
        ? 'bg-sky-950/40 border-sky-800/60'
        : 'bg-zinc-950 border-zinc-800'}"
    >
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <span
        class="{changedIndices.has(i)
          ? 'text-sky-300'
          : 'text-sky-400'} font-bold text-sm cursor-pointer select-none hover:text-sky-200 transition-colors"
        title="Click to toggle canonical names"
        onclick={() => (showCanonicalNames = !showCanonicalNames)}
        >{getRegName(i, showCanonicalNames)}</span
      >
      <span
        class="{changedIndices.has(i)
          ? 'text-amber-200 font-semibold'
          : 'text-orange-300'} text-sm transition-colors"
        >{formatReg(value)}</span
      >
    </div>
  {/each}
</div>
