<script lang="ts">
  import { fileStore } from "$lib/store/fileStore.svelte";
  import type { IconName } from "$lib/types";
  import Icon from "../../Icon.svelte";
  import StyleSettings from "./StyleSettings.svelte";
  import PanelControls from "./PanelControls.svelte";

  let viewOpen = $state(false);
  let showSettings = $state(false);
</script>

<div class="flex items-center gap-0.5">
  {#snippet control(
    title: string,
    iconName: IconName,
    onClick: () => void,
    isActive?: boolean,
  )}
    <button
      class="grid h-8 w-8 place-items-center rounded-md transition-colors hover:bg-surface-3 {isActive
        ? 'text-primary'
        : 'text-text-faint hover:text-text-dim'}"
      {title}
      onclick={onClick}
    >
      <Icon name={iconName} class="h-3.75 w-3.75" />
    </button>
  {/snippet}

  {@render control("Open file", "folder", () => fileStore.handleOpenFile())}
  {@render control("Save file", "save", () => fileStore.handleSaveFile())}

  <div class="relative">
    {@render control(
      "Panels",
      "panels",
      () => (viewOpen = !viewOpen),
      viewOpen,
    )}
    {#if viewOpen}
      <PanelControls bind:viewOpen />
    {/if}
  </div>

  <div class="relative">
    {@render control(
      "Theme",
      "sliders",
      () => (showSettings = !showSettings),
      showSettings,
    )}
    {#if showSettings}
      <StyleSettings bind:showSettings />
    {/if}
  </div>
</div>
