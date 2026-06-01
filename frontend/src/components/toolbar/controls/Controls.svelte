<script lang="ts">
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { keymap } from "$lib/keymap.svelte";
  import { modeStore, toggleMode } from "$lib/store/mode.svelte";
  import IconButton from "../../ui/IconButton.svelte";
  import StyleSettings from "./StyleSettings.svelte";
  import PanelControls from "./PanelControls.svelte";

  let viewOpen = $state(false);
  let showSettings = $state(false);
</script>

<div class="flex items-center gap-0.5">
  <IconButton
    name="folder"
    title={`Open file (${keymap.describe("open")})`}
    onclick={() => fileStore.handleOpenFile()}
  />
  <IconButton
    name="save"
    title={`Save file (${keymap.describe("save")})`}
    onclick={() => fileStore.handleSaveFile()}
  />

  <div class="relative">
    <IconButton
      name="panels"
      title="Panels"
      active={viewOpen}
      onclick={() => (viewOpen = !viewOpen)}
    />
    <PanelControls bind:open={viewOpen} />
  </div>

  <IconButton
    name={modeStore.mode === "light" ? "moon" : "sun"}
    title={modeStore.mode === "light"
      ? "Switch to dark mode"
      : "Switch to light mode"}
    onclick={toggleMode}
  />

  <div class="relative">
    <IconButton
      name="sliders"
      title="Theme"
      active={showSettings}
      onclick={() => (showSettings = !showSettings)}
    />
    <StyleSettings bind:open={showSettings} />
  </div>
</div>
