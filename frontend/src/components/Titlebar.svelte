<script lang="ts">
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { onMount } from "svelte";
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import Icon from "./Icon.svelte";

  const appWindow = getCurrentWindow();
  let isMaximized = $state(false);

  const debugging = $derived(
    cpuStore.cpuState != null && cpuStore.cpuState.status !== "Paused",
  );

  async function syncMaximized() {
    isMaximized = await appWindow.isMaximized();
  }

  onMount(() => {
    syncMaximized();
    const unlisten = appWindow.onResized(syncMaximized);
    return () => {
      unlisten.then((fn) => fn());
    };
  });
</script>

<header
  data-tauri-drag-region
  class="relative flex h-10 flex-none select-none items-center gap-3.5 border-b border-border bg-linear-to-b from-surface-2 to-surface-1 px-3"
>
  <div
    data-tauri-drag-region
    class="flex items-center gap-2 text-[11px] font-semibold uppercase tracking-[1.5px] text-text-faint"
  >
    HART
  </div>

  <div
    data-tauri-drag-region
    class="pointer-events-none absolute left-1/2 top-0 bottom-0 flex -translate-x-1/2 items-center gap-2.5 text-[12.5px] font-medium tracking-[0.2px] text-text-dim"
  >
    <span>HART</span>
    <span class="h-0.75 w-0.75 rounded-full bg-text-ghost"></span>
    <span class="text-text">{fileStore.activeFile.name}</span>
    {#if debugging}
      <span
        class="h-1.75 w-1.75 rounded-full bg-primary shadow-[0_0_8px_var(--primary-glow)] animate-pulse"
        title="debugging session active"
      ></span>
    {/if}
  </div>

  <div class="ml-auto flex items-center gap-1">
    <button
      class="grid h-7 w-8 place-items-center rounded-md text-text-faint transition-colors hover:bg-surface-3 hover:text-text"
      title="Minimize"
      onclick={() => appWindow.minimize()}
    >
      <Icon name="min" class="h-4 w-4" />
    </button>
    <button
      class="grid h-7 w-8 place-items-center rounded-md text-text-faint transition-colors hover:bg-surface-3 hover:text-text"
      title={isMaximized ? "Restore" : "Maximize"}
      onclick={() => appWindow.toggleMaximize()}
    >
      <Icon name={isMaximized ? "restore" : "max"} class="h-4 w-4" />
    </button>
    <button
      class="grid h-7 w-8 place-items-center rounded-md text-text-faint transition-colors hover:bg-red hover:text-white"
      title="Close"
      onclick={() => appWindow.close()}
    >
      <Icon name="close" class="h-4 w-4" />
    </button>
  </div>
</header>
