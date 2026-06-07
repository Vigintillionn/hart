<script lang="ts">
  import { layoutStore } from "$lib/store/layoutStore.svelte";
  import Popover from "../../ui/Popover.svelte";

  let { open = $bindable() }: { open: boolean } = $props();
</script>

<Popover bind:open width="w-52">
  <div class="py-1.5">
    {#snippet item(label: string, on: boolean, toggle: () => void)}
      <button
        class="flex w-full items-center gap-2.5 px-3.5 py-1.5 text-left text-[12.5px] text-text-dim transition-colors hover:bg-surface-3"
        onclick={toggle}
      >
        <span class="w-3 text-primary">{on ? "✓" : ""}</span>{label}
      </button>
    {/snippet}
    {@render item("Debug Panel", layoutStore.isDebugVisible, () =>
      layoutStore.toggleDebug(),
    )}
    {@render item(
      "Registers",
      layoutStore.isDebugVisible && layoutStore.isRegistersVisible,
      () => layoutStore.toggleRegisters(),
    )}

    {@render item(
      "Memory",
      layoutStore.isDebugVisible && layoutStore.isMemoryVisible,
      () => layoutStore.toggleMemory(),
    )}
    {@render item("Console", layoutStore.isConsoleVisible, () =>
      layoutStore.toggleConsole(),
    )}
    <div class="my-1 h-px bg-border"></div>
    <button
      class="flex w-full items-center gap-2.5 px-3.5 py-1.5 text-left text-[12.5px] text-text-faint transition-colors hover:bg-surface-3"
      onclick={() => layoutStore.resetLayout()}
    >
      <span class="w-3">↻</span>Reset layout
    </button>
  </div>
</Popover>
