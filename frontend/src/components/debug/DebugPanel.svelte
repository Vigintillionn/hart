<script lang="ts">
  import { PaneGroup, Pane } from "paneforge";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { layoutStore, PANE_KEYS } from "$lib/store/layoutStore.svelte";
  import CpuHeader from "./CpuHeader.svelte";
  import RegisterPane from "./RegisterPane.svelte";
  import MemoryPane from "./MemoryPane.svelte";
  import CollapsibleResizer from "../ui/CollapsibleResizer.svelte";
</script>

<div class="flex h-full min-h-0 flex-col bg-surface-1">
  <CpuHeader />

  {#if cpuStore.cpuState}
    <div class="min-h-0 flex-1">
      <PaneGroup direction="vertical" autoSaveId={PANE_KEYS.debugV}>
        <Pane
          defaultSize={62}
          minSize={12}
          collapsible
          collapsedSize={0}
          bind:this={layoutStore.registersPaneRef}
          onCollapse={() => (layoutStore.isRegistersVisible = false)}
          onExpand={() => (layoutStore.isRegistersVisible = true)}
        >
          <RegisterPane
            registers={cpuStore.cpuState.regs}
            csrs={cpuStore.cpuState.csrs}
          />
        </Pane>

        <CollapsibleResizer
          direction="vertical"
          pane={layoutStore.memoryPaneRef}
        />

        <Pane
          defaultSize={38}
          minSize={12}
          collapsible
          collapsedSize={0}
          bind:this={layoutStore.memoryPaneRef}
          onCollapse={() => (layoutStore.isMemoryVisible = false)}
          onExpand={() => (layoutStore.isMemoryVisible = true)}
        >
          <MemoryPane mem={cpuStore.cpuState.mem} />
        </Pane>
      </PaneGroup>
    </div>
  {:else}
    <div
      class="flex flex-1 items-center justify-center px-6 text-center font-mono text-[11.5px] text-text-ghost"
    >
      — compile a program to inspect CPU state —
    </div>
  {/if}
</div>
