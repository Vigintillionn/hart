<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { PaneGroup, Pane } from "paneforge";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { confirm } from "@tauri-apps/plugin-dialog";
  import Toolbar from "../components/toolbar/Toolbar.svelte";
  import Editor from "../components/ide/Editor.svelte";
  import DebugPanel from "../components/debug/DebugPanel.svelte";
  import TerminalContainer from "../components/ide/TerminalContainer.svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { layoutStore, PANE_KEYS } from "$lib/store/layoutStore.svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import { keymap } from "$lib/keymap.svelte";
  import CollapsibleResizer from "../components/ui/CollapsibleResizer.svelte";
  import SettingsWindow from "../components/settings/SettingsWindow.svelte";

  onMount(() => {
    cpuStore.initListener();

    const unlistenClose = getCurrentWindow().onCloseRequested(async (event) => {
      if (!fileStore.hasUnsavedChanges) return;
      const quit = await confirm("You have unsaved changes. Quit anyway?", {
        title: "Unsaved changes",
        kind: "warning",
      });
      if (!quit) event.preventDefault();
    });

    return () => unlistenClose.then((fn) => fn());
  });
  onDestroy(() => cpuStore.cleanup());
</script>

<svelte:window onkeydown={keymap.handleKeydown} />

{#if !cpuStore.sidecarAlive}
  <div
    class="flex flex-none items-center justify-center gap-2 border-b border-red bg-red/15 px-4 py-1.5 text-[12px] font-medium text-red"
    role="alert"
  >
    Emulator process stopped unexpectedly. Save your work, then restart HART.
  </div>
{/if}

<Toolbar />
<div class="min-h-0 flex-1" inert={settingsStore.open}>
  <PaneGroup direction="horizontal" autoSaveId={PANE_KEYS.mainH}>
    <Pane defaultSize={68} minSize={32}>
      <PaneGroup direction="vertical" autoSaveId={PANE_KEYS.leftV}>
        <Pane defaultSize={72} minSize={25}>
          <Editor />
        </Pane>

        <CollapsibleResizer
          direction="vertical"
          pane={layoutStore.consolePaneRef}
        />

        <Pane
          defaultSize={28}
          minSize={10}
          collapsible
          collapsedSize={0}
          bind:this={layoutStore.consolePaneRef}
          onCollapse={() => (layoutStore.isConsoleVisible = false)}
          onExpand={() => (layoutStore.isConsoleVisible = true)}
        >
          <TerminalContainer />
        </Pane>
      </PaneGroup>
    </Pane>

    <CollapsibleResizer direction="horizontal" pane={layoutStore.debugPaneRef} />

    <Pane
      defaultSize={32}
      minSize={20}
      collapsible
      collapsedSize={0}
      bind:this={layoutStore.debugPaneRef}
      onCollapse={() => (layoutStore.isDebugVisible = false)}
      onExpand={() => (layoutStore.isDebugVisible = true)}
    >
      <DebugPanel />
    </Pane>
  </PaneGroup>
</div>

<SettingsWindow />
