<script lang="ts">
  import { layoutStore } from "$lib/store/layoutStore.svelte";
</script>

{#snippet modeButton(label: string, isHex: boolean)}
  <button
    class="rounded-[5px] px-2.5 py-1 font-mono text-[11px] font-semibold tracking-[0.3px] transition-colors {layoutStore.hexMode ===
    isHex
      ? 'bg-surface-3 text-primary'
      : 'text-text-faint hover:text-text-dim'}"
    onclick={() => (layoutStore.hexMode = isHex)}
  >
    {label}
  </button>
{/snippet}

<div
  class="inline-flex gap-0.5 rounded-md border border-border bg-surface-0 p-0.5"
>
  {@render modeButton("HEX", true)}
  {@render modeButton("DEC", false)}
</div>
