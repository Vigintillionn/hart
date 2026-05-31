<script lang="ts">
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { layoutStore } from "$lib/store/layoutStore.svelte";
  import { toHex, hex32 } from "$lib/util";

  const st = $derived(cpuStore.cpuState);
  const pcToLine = $derived(cpuStore.sourceLineMap);
  const pcToDisasm = $derived(cpuStore.disasmTextMap);

  const curInstr = $derived.by(() => {
    if (!st) return null;
    const disasm = pcToDisasm.get(st.pc);
    if (disasm) return disasm;
    const line = pcToLine.get(st.pc);
    if (!line) return null;
    const text = fileStore.activeFile.content.split("\n")[line - 1] ?? "";
    return text.trim().replace(/\s*#.*$/, "") || null;
  });

  const pcText = $derived(
    st ? (layoutStore.hexMode ? toHex(st.pc) : (st.pc >>> 0).toString()) : "",
  );
</script>

<div
  class="flex-none border-b border-border bg-linear-to-b from-surface-2 to-surface-1 px-4 pb-3.5 pt-3"
>
  <div class="mb-3 flex items-center gap-2">
    <span
      class="text-[11px] font-semibold uppercase tracking-[1.6px] text-text-dim"
      >CPU State</span
    >
  </div>

  <div class="grid grid-cols-2 gap-2">
    <div class="rounded-md border border-border bg-surface-0 px-2.5 py-2.5">
      <div class="mb-1 text-[9.5px] uppercase tracking-[1.2px] text-text-faint">
        Program Counter
      </div>
      <div
        class="font-mono text-base font-semibold tracking-[0.3px] text-primary"
      >
        {#if st && layoutStore.hexMode}<span class="text-text-faint">0x</span
          >{hex32(st.pc)}{:else}{pcText}{/if}
      </div>
    </div>
    <div class="rounded-md border border-border bg-surface-0 px-2.5 py-2.5">
      <div class="mb-1 text-[9.5px] uppercase tracking-[1.2px] text-text-faint">
        Cycles
      </div>
      <div class="font-mono text-base font-semibold tracking-[0.3px] text-text">
        {(st?.cycles ?? 0).toLocaleString()}
      </div>
    </div>
  </div>

  <div class="mt-2.5 flex items-center gap-2 font-mono text-[11px]">
    <span class="text-text-ghost">▸</span>
    <span class="text-text-faint">{curInstr && st ? toHex(st.pc) : ""}</span>
    <span class={curInstr ? "text-secondary" : "text-text-ghost"}
      >{curInstr ?? "idle"}</span
    >
  </div>
</div>
