<script lang="ts" generics="T">
  let {
    options,
    value = $bindable(),
    size = "md",
    accent = "primary",
  }: {
    options: { value: T; label: string }[];
    value: T;
    size?: "sm" | "md";
    accent?: "primary" | "text";
  } = $props();

  const item = $derived(
    size === "sm"
      ? "rounded-sm px-2 py-0.5 text-[10px] uppercase tracking-[1px]"
      : "rounded-[5px] px-2.5 py-1 font-mono text-[11px] tracking-[0.3px]",
  );
  const activeText = $derived(
    accent === "primary" ? "text-primary" : "text-text",
  );
</script>

<div
  class="inline-flex gap-0.5 rounded-md border border-border bg-surface-0 p-0.5"
>
  {#each options as opt (String(opt.value))}
    <button
      class="font-semibold cursor-pointer transition-colors {item} {value ===
      opt.value
        ? `bg-surface-3 ${activeText}`
        : 'text-text-faint hover:text-text-dim'}"
      aria-pressed={value === opt.value}
      onclick={() => (value = opt.value)}>{opt.label}</button
    >
  {/each}
</div>
