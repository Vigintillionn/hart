<script lang="ts">
  import { themeColors } from "$lib/editor/theme.svelte";

  let { showSettings = $bindable() }: { showSettings: boolean } = $props();

  const fields: { key: keyof typeof themeColors; label: string }[] = [
    { key: "background", label: "Editor background" },
    { key: "keyword", label: "Instructions (li, add)" },
    { key: "register", label: "Registers (x0, a0)" },
    { key: "directive", label: "Directives (.text)" },
    { key: "number", label: "Numbers (100, 0x10)" },
    { key: "string", label: 'Strings ("...")' },
    { key: "comment", label: "Comments (#)" },
  ];
</script>

<div
  class="absolute right-0 top-full z-50 flex w-72 flex-col overflow-hidden rounded-lg border border-border-strong bg-surface-2 shadow-2xl"
>
  <div
    class="flex items-center justify-between border-b border-border bg-surface-1 px-4 py-3"
  >
    <h3
      class="text-[11px] font-semibold uppercase tracking-[1.5px] text-text-dim"
    >
      Syntax Theme
    </h3>
    <button
      class="text-lg leading-none text-text-faint transition-colors hover:text-text"
      onclick={() => (showSettings = false)}>×</button
    >
  </div>
  <div class="flex flex-col gap-2.5 p-4">
    {#each fields as { key, label }}
      <label
        class="flex items-center justify-between text-[12.5px] text-text-dim"
      >
        <span>{label}</span>
        <input
          type="color"
          class="h-7 w-7 cursor-pointer rounded border border-border bg-transparent p-0"
          bind:value={themeColors[key]}
        />
      </label>
    {/each}
  </div>
</div>
