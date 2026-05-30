<script lang="ts">
  import { cpuStore } from "$lib/cpuStore.svelte";
  import CpuHeader from "./CpuHeader.svelte";
  import RegisterFile from "./RegisterFile.svelte";
  import MemoryView from "./MemoryView.svelte";
  import { PaneGroup, Pane, PaneResizer } from "paneforge";
  import { layoutStore } from "$lib/layoutStore.svelte";
  import { toHex } from "$lib/util";

  let pcShowHex = $state(true);
</script>

<div class="flex flex-col h-full overflow-hidden">
  <CpuHeader />

  {#if cpuStore.cpuState}
    <div class="flex-1 min-h-0">
      <PaneGroup direction="vertical" autoSaveId="debug-panel-layout">
        <Pane
          defaultSize={65}
          minSize={10}
          collapsible={true}
          collapsedSize={0}
          bind:this={layoutStore.registersPaneRef}
          onCollapse={() => (layoutStore.isRegistersVisible = false)}
          onExpand={() => (layoutStore.isRegistersVisible = true)}
        >
          <div class="h-full overflow-y-auto p-4 min-h-0 bg-zinc-900">
            <RegisterFile registers={cpuStore.cpuState.regs} />
          </div>
        </Pane>

        <PaneResizer
          class="h-1 bg-zinc-800 hover:bg-zinc-600 data-[resize-handle-state=drag]:bg-sky-500 transition-colors cursor-row-resize relative z-10 flex items-center justify-center"
        >
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="absolute inset-x-0 -top-1.5 -bottom-1.5"
            ondblclick={() =>
              layoutStore.memoryPaneRef?.isCollapsed()
                ? layoutStore.memoryPaneRef?.expand()
                : layoutStore.memoryPaneRef?.collapse()}
          ></div>
        </PaneResizer>

        <Pane
          defaultSize={35}
          minSize={10}
          collapsible={true}
          collapsedSize={0}
          bind:this={layoutStore.memoryPaneRef}
          onCollapse={() => (layoutStore.isMemoryVisible = false)}
          onExpand={() => (layoutStore.isMemoryVisible = true)}
        >
          <div class="h-full flex flex-col min-h-0 bg-zinc-900">
            <MemoryView mem={cpuStore.cpuState.mem} />
          </div>
        </Pane>
      </PaneGroup>
    </div>
  {:else}
    <div
      class="flex items-center justify-center h-32 text-zinc-600 italic text-sm flex-1"
    >
      Awaiting compilation...
    </div>
  {/if}
</div>
