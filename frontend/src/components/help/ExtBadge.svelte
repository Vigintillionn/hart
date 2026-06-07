<script lang="ts">
  let { code, enabled = true }: { code: string; enabled?: boolean } = $props();
</script>

<span
  class={[
    "flex h-5 min-w-5 flex-none items-center justify-center rounded border px-1 font-semibold",
    code.length > 1 ? "text-[9px]" : "text-[11px]",
    enabled
      ? "border-primary/40 bg-primary-soft text-primary"
      : "border-border text-text-faint",
  ]}
>
  {code}
</span>
