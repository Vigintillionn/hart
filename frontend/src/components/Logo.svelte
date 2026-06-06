<script lang="ts">
  let { class: cls = "" }: { class?: string } = $props();
</script>

<div class="flex items-center gap-2.5 pr-1.5 {cls}">
  <div
    class="grid h-7.5 w-7.5 place-items-center rounded-lg border border-border-strong bg-linear-to-br from-surface-3 to-surface-0 shadow-[inset_0_1px_0_rgba(255,255,255,0.05)]"
  >
    <img src="/logo.svg" alt="Hart Logo" class="h-4 w-4" />
  </div>
  <div class="leading-none">
    <div class="text-[15px] font-bold tracking-[1.5px] text-text">
      HA<span class="text-primary">R</span>T
    </div>
    <div class="mt-0.5 text-[9px] uppercase tracking-[1.5px] text-text-faint">
      RISC-V
    </div>
  </div>
</div>
