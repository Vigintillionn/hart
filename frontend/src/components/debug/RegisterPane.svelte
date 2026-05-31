<script lang="ts">
  import type { CpuState } from "../../bindings/CpuState";
  import CsrFile from "./registers/CsrFile.svelte";
  import RegisterFile from "./registers/RegisterFile.svelte";

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

    <div class="flex rounded-[5px] border border-border bg-surface-0 p-px">
      {#snippet seg(label: string, active: boolean, onClick: () => void)}
        <button
          class="rounded-sm px-2 py-0.5 text-[10px] font-semibold uppercase tracking-[1px] transition-colors {active
            ? 'bg-surface-3 text-text'
            : 'text-text-faint hover:text-text-dim'}"
          onclick={onClick}>{label}</button
        >
      {/snippet}
      {@render seg("Registers", view === "regs", () => (view = "regs"))}
      {@render seg("CSRs", view === "csrs", () => (view = "csrs"))}
    </div>

    <span class="ml-auto font-mono text-[10px] text-text-faint">
      {view === "regs" ? "x0 – x31" : "control & status"}
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
