<script lang="ts">
  import type { CpuState } from "../../bindings/CpuState";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import MemoryView from "./MemoryView.svelte";
  import TextSegmentView from "./TextSegmentView.svelte";
  import SegmentedControl from "../ui/SegmentedControl.svelte";

  let { mem }: { mem: CpuState["mem"] } = $props();

  let view = $state<"mem" | "text">("mem");
  const instrCount = $derived(cpuStore.textRows.length);
</script>

<div class="flex h-full min-h-0 flex-col">
  <div
    class="flex h-8.25 flex-none items-center gap-2 border-b border-border bg-surface-1 px-4"
  >
    <span
      class="h-2.75 w-0.75 rounded-sm {view === 'mem'
        ? 'bg-primary'
        : 'bg-secondary'}"
    ></span>

    <SegmentedControl
      bind:value={view}
      size="sm"
      accent="text"
      options={[
        { value: "mem", label: "Memory" },
        { value: "source", label: "Source" },
      ]}
    />

    <span class="ml-auto font-mono text-[10px] text-text-faint">
      {view === "mem"
        ? `${mem.length.toLocaleString()} bytes`
        : `${instrCount.toLocaleString()} instr`}
    </span>
  </div>

  <div class="min-h-0 flex-1">
    {#if view === "mem"}
      <MemoryView {mem} />
    {:else}
      <TextSegmentView />
    {/if}
  </div>
</div>
