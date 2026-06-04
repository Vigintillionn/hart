<script lang="ts">
  let { code, enabled = true }: { code: string; enabled?: boolean } = $props();
</script>

<span
  class={[
    "flex h-5 w-5 flex-none items-center justify-center rounded border text-[11px] font-semibold",
    enabled
      ? "border-primary/40 bg-primary-soft text-primary"
      : "border-border text-text-faint",
  ]}
>
  {code}
</span>
