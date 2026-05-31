<script lang="ts">
  let { class: cls = "" }: { class?: string } = $props();
</script>

<div class="flex items-center gap-2.5 pr-1.5 {cls}">
  <div
    class="grid h-7.5 w-7.5 place-items-center rounded-lg border border-border-strong bg-linear-to-br from-surface-3 to-surface-0 shadow-[inset_0_1px_0_rgba(255,255,255,0.05)]"
  >
    <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none">
      <polyline
        points="2,13 6.5,13 8.5,13 10,7.5 13,16.5 14.6,11.5 16,13 22,13"
        stroke="var(--color-primary)"
        stroke-width="1.9"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
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
