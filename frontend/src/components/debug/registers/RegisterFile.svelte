<script lang="ts">
  import { layoutStore } from "$lib/store/layoutStore.svelte";
  import { displayStore } from "$lib/store/displayStore.svelte";
  import { fmtRegisterValue, getRegName } from "$lib/util";
  import type { CpuState } from "../../../bindings/CpuState";
  import { createChangeFlasher } from "$lib/changeFlasher.svelte";

  let { registers }: { registers: CpuState["regs"] } = $props();

  const SPECIAL = new Set([1, 2, 3, 8]); // ra, sp, gp, fp
  const registerFlasher = createChangeFlasher(() => registers);
</script>

<div class="grid grid-cols-2 gap-px bg-border-soft">
  {#each registers as value, i (i)}
    {@const isZero = value === 0}
    {@const isChanged = registerFlasher.changed.has(i) && displayStore.flashChanges}
    {@const abi = displayStore.registerNaming === "abi"}
    {@const primary = abi ? getRegName(i, true) : `x${i}`}
    {@const secondary =
      (abi ? `x${i}` : getRegName(i, true)) + (i === 8 ? "/fp" : "")}
    <div
      class="relative flex items-baseline gap-2 px-2.5 py-1.5 transition-colors {isChanged
        ? "bg-secondary-soft before:absolute before:inset-y-0 before:left-0 before:w-0.5 before:bg-secondary before:content-['']"
        : 'bg-surface-1 hover:bg-surface-2'}"
    >
      <span
        class="min-w-7.5 font-mono text-[11.5px] font-semibold {SPECIAL.has(i)
          ? 'text-secondary'
          : 'text-text-dim'}">{primary}</span
      >
      <span class="min-w-5.5 font-mono text-[9px] text-text-ghost">{secondary}</span>
      <span
        class="ml-auto font-mono text-[11.5px] tracking-[0.2px] {isChanged
          ? 'text-secondary'
          : isZero
            ? 'text-text-faint'
            : 'text-text'}"
      >
        {#if layoutStore.hexMode}<span class="text-text-ghost">0x</span
          >{/if}{fmtRegisterValue(value, layoutStore.hexMode)}
      </span>
    </div>
  {/each}
</div>
