<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { PaneGroup, Pane, PaneResizer } from "paneforge";
  import Editor from "../components/Editor.svelte";
  import Header from "../components/Header.svelte";
  import StyleSettings from "../components/StyleSettings.svelte";
  import TerminalContainer from "../components/TerminalContainer.svelte";
  import DebugPanel from "../components/DebugPanel.svelte";
  import { cpuStore } from "$lib/cpuStore.svelte";
  import { layoutStore } from "$lib/layoutStore.svelte";

  let showSettings = $state(false);

  onMount(() => {
    cpuStore.initListener();
  });

  onDestroy(() => {
    cpuStore.cleanup();
  });
</script>

<div
  class="flex flex-col h-screen w-screen relative bg-zinc-950 text-zinc-300 font-sans overflow-hidden"
>
  <Header bind:showSettings />
  {#if showSettings}
    <StyleSettings bind:showSettings />
  {/if}

  <div class="flex-1 overflow-hidden">
    <PaneGroup direction="vertical" autoSaveId="app-layout-vertical">
      <Pane defaultSize={70} minSize={20}>
        <PaneGroup direction="horizontal" autoSaveId="app-layout-horizontal">
          <Pane defaultSize={60} minSize={20}>
            <section class="flex flex-col h-full min-w-0 bg-zinc-900">
              <Editor />
            </section>
          </Pane>

          <PaneResizer
            class="w-1 bg-zinc-800 hover:bg-zinc-600 data-[resize-handle-state=drag]:bg-sky-500 transition-colors cursor-col-resize relative z-10 flex items-center justify-center"
          >
            <!-- svelte-ignore a11y_no_static_element_interactions -->
            <div
              class="absolute inset-y-0 -left-1.5 -right-1.5"
              ondblclick={() =>
                layoutStore.cpuPaneRef?.isCollapsed()
                  ? layoutStore.cpuPaneRef?.expand()
                  : layoutStore.cpuPaneRef?.collapse()}
            ></div>
          </PaneResizer>

          <Pane
            defaultSize={40}
            minSize={20}
            collapsible={true}
            collapsedSize={0}
            bind:this={layoutStore.cpuPaneRef}
            onCollapse={() => (layoutStore.isCpuVisible = false)}
            onExpand={() => (layoutStore.isCpuVisible = true)}
          >
            <aside class="flex flex-col h-full min-w-0 bg-zinc-900">
              <DebugPanel />
            </aside>
          </Pane>
        </PaneGroup>
      </Pane>

      <PaneResizer
        class="h-1 bg-zinc-800 hover:bg-zinc-600 data-[resize-handle-state=drag]:bg-sky-500 transition-colors cursor-row-resize relative z-10 flex items-center justify-center"
      >
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div
          class="absolute inset-x-0 -top-1.5 -bottom-1.5"
          ondblclick={() =>
            layoutStore.terminalPaneRef?.isCollapsed()
              ? layoutStore.terminalPaneRef?.expand()
              : layoutStore.terminalPaneRef?.collapse()}
        ></div>
      </PaneResizer>

      <Pane
        defaultSize={30}
        minSize={10}
        collapsible={true}
        collapsedSize={0}
        bind:this={layoutStore.terminalPaneRef}
        onCollapse={() => (layoutStore.isTerminalVisible = false)}
        onExpand={() => (layoutStore.isTerminalVisible = true)}
      >
        <footer class="flex flex-col h-full min-h-0 bg-zinc-900">
          <TerminalContainer />
        </footer>
      </Pane>
    </PaneGroup>
  </div>
</div>
