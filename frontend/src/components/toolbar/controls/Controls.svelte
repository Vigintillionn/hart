<script lang="ts">
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { keymap } from "$lib/keymap.svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import IconButton from "../../ui/IconButton.svelte";
  import PanelControls from "./PanelControls.svelte";

  let viewOpen = $state(false);
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
    name="sliders"
    title="Settings"
    active={settingsStore.open}
    onclick={() => settingsStore.toggle()}
  />
</div>
