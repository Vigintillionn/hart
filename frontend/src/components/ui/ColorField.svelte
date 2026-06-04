<script lang="ts">
  let { value = $bindable("#000000") }: { value?: string } = $props();
</script>

<label class="flex cursor-pointer items-center gap-2.5">
  <span class="font-mono text-[11px] uppercase tracking-[0.5px] text-text-dim">
    {value}
  </span>
  <span
    class="relative grid h-7 w-7 place-items-center overflow-hidden rounded border border-border"
    style:background={value}
  >
    <input
      type="color"
      bind:value
      class="absolute inset-[-25%] h-[150%] w-[150%] cursor-pointer border-0 bg-transparent p-0"
      aria-label="Pick colour"
    />
  </span>
</label>
