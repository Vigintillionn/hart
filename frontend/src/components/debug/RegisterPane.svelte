<script lang="ts">
  import type { CpuState } from "../../bindings/CpuState";
  import CsrFile from "./registers/CsrFile.svelte";
  import RegisterFile from "./registers/RegisterFile.svelte";
  import SegmentedControl from "../ui/SegmentedControl.svelte";

  let {
    registers,
    csrs,
  }: { registers: CpuState["regs"]; csrs: CpuState["csrs"] } = $props();

  let view = $state<"regs" | "csrs">("regs");
</script>

<div class="flex h-full min-h-0 flex-col">
  <div
    class="flex h-8.25 flex-none items-center gap-2 border-b border-border bg-surface-1 px-4"
  >
    <span
      class="h-2.75 w-0.75 rounded-sm {view === 'regs'
        ? 'bg-secondary'
        : 'bg-amber'}"
    ></span>

    <SegmentedControl
      bind:value={view}
      size="sm"
      accent="text"
      options={[
        { value: "regs", label: "Registers" },
        { value: "csrs", label: "CSRs" },
      ]}
    />

    <span class="ml-auto font-mono text-[10px] text-text-faint">
      {view === "regs" ? "x0 - x31" : "control & status"}
    </span>
  </div>

  <div class="scroll-thin min-h-0 flex-1 overflow-auto">
    {#if view === "regs"}
      <RegisterFile {registers} />
    {:else}
      <CsrFile {csrs} />
    {/if}
  </div>
</div>
