<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { PaneGroup, Pane, PaneResizer } from "paneforge";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { confirm } from "@tauri-apps/plugin-dialog";
  import Toolbar from "../components/toolbar/Toolbar.svelte";
  import Editor from "../components/ide/Editor.svelte";
  import DebugPanel from "../components/debug/DebugPanel.svelte";
  import TerminalContainer from "../components/ide/TerminalContainer.svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { layoutStore, PANE_KEYS } from "$lib/store/layoutStore.svelte";
  import { keymap } from "$lib/keymap.svelte";

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
<div class="min-h-0 flex-1">
  <PaneGroup direction="horizontal" autoSaveId={PANE_KEYS.mainH}>
    <Pane defaultSize={68} minSize={32}>
      <PaneGroup direction="vertical" autoSaveId={PANE_KEYS.leftV}>
        <Pane defaultSize={72} minSize={25}>
          <Editor />
        </Pane>

        <PaneResizer
          class="relative z-10 h-px bg-border transition-colors data-[resize-handle-state=hover]:bg-primary-soft data-[resize-handle-state=drag]:bg-primary"
        >
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="absolute inset-x-0 -top-1 -bottom-1 cursor-row-resize"
            ondblclick={() =>
              layoutStore.consolePaneRef?.isCollapsed()
                ? layoutStore.consolePaneRef?.expand()
                : layoutStore.consolePaneRef?.collapse()}
          ></div>
        </PaneResizer>

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

    <PaneResizer
      class="relative z-10 w-px bg-border transition-colors data-[resize-handle-state=hover]:bg-primary-soft data-[resize-handle-state=drag]:bg-primary"
    >
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="absolute inset-y-0 -left-1 -right-1 cursor-col-resize"
        ondblclick={() =>
          layoutStore.debugPaneRef?.isCollapsed()
            ? layoutStore.debugPaneRef?.expand()
            : layoutStore.debugPaneRef?.collapse()}
      ></div>
    </PaneResizer>

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
