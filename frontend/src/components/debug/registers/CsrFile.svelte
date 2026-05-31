<script lang="ts">
  import { createChangeFlasher } from "$lib/changeFlasher.svelte";
  import { layoutStore } from "$lib/store/layoutStore.svelte";
  import {
    fmtRegisterValue,
    getCsrDescription,
    getCsrName,
    hex12,
  } from "$lib/util";
  import type { CpuState } from "../../../bindings/CpuState";

  let { csrs }: { csrs: CpuState["csrs"] } = $props();

  const csrRows = $derived([...csrs].sort((a, b) => a[0] - b[0]));
  const csrFlasher = createChangeFlasher(() => new Map(csrs));
</script>

{#if csrRows.length === 0}
  <div
    class="flex h-full items-center justify-center px-6 text-center font-mono text-[11px] text-text-ghost"
  >
    — no CSRs written yet —
  </div>
{:else}
  <div class="flex flex-col gap-px bg-border-soft">
    {#each csrRows as [addr, value] (addr)}
      {@const isChanged = csrFlasher.changed.has(addr)}
      {@const isZero = value === 0}
      <div
        class="relative flex items-baseline gap-2 px-2.5 py-1.5 transition-colors {isChanged
          ? "bg-primary-soft before:absolute before:inset-y-0 before:left-0 before:w-0.5 before:bg-primary before:content-['']"
          : 'bg-surface-1 hover:bg-surface-2'}"
        title={getCsrDescription(addr)}
      >
        <span class="min-w-15 font-mono text-[11.5px] font-semibold text-amber"
          >{getCsrName(addr)}</span
        >
        <span class="min-w-9 font-mono text-[9px] text-text-ghost"
          >{hex12(addr)}</span
        >
        <span
          class="ml-auto font-mono text-[11.5px] tracking-[0.2px] {isChanged
            ? 'text-primary'
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
{/if}
