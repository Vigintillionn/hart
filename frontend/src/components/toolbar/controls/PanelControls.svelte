<script lang="ts">
  import { layoutStore } from "$lib/store/layoutStore.svelte";

  let { viewOpen = $bindable() }: { viewOpen: boolean } = $props();
</script>

<button
  class="fixed inset-0 z-40 cursor-default"
  aria-label="Close menu"
  onclick={() => (viewOpen = false)}
></button>
<div
  class="absolute right-0 top-full z-50 mt-1.5 w-52 overflow-hidden rounded-lg border border-border-strong bg-surface-2 py-1.5 shadow-2xl"
>
  {#snippet item(label: string, on: boolean, toggle: () => void)}
    <button
      class="flex w-full items-center gap-2.5 px-3.5 py-1.5 text-left text-[12.5px] text-text-dim transition-colors hover:bg-surface-3"
      onclick={toggle}
    >
      <span class="w-3 text-primary">{on ? "✓" : ""}</span>{label}
    </button>
  {/snippet}
  {@render item("Debug Panel", layoutStore.isDebugVisible, () =>
    layoutStore.toggleDebug(!layoutStore.isDebugVisible),
  )}
  {@render item("Registers", layoutStore.isRegistersVisible, () =>
    layoutStore.toggleRegisters(!layoutStore.isRegistersVisible),
  )}
  {@render item("Memory", layoutStore.isMemoryVisible, () =>
    layoutStore.toggleMemory(!layoutStore.isMemoryVisible),
  )}
  {@render item("Console", layoutStore.isConsoleVisible, () =>
    layoutStore.toggleConsole(!layoutStore.isConsoleVisible),
  )}
  <div class="my-1 h-px bg-border"></div>
  <button
    class="flex w-full items-center gap-2.5 px-3.5 py-1.5 text-left text-[12.5px] text-text-faint transition-colors hover:bg-surface-3"
    onclick={() => layoutStore.resetLayout()}
  >
    <span class="w-3">↻</span>Reset layout
  </button>
</div>
