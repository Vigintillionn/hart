<script lang="ts">
  import {
    darkTheme,
    lightTheme,
    resetActiveTheme,
    type ThemeColors,
  } from "$lib/editor/theme.svelte";
  import { modeStore } from "$lib/store/mode.svelte";
  import Popover from "../../ui/Popover.svelte";

  let { open = $bindable() }: { open: boolean } = $props();

  const palette = $derived(modeStore.mode === "light" ? lightTheme : darkTheme);

  const fields: { key: keyof ThemeColors; label: string }[] = [
    { key: "background", label: "Editor background" },
    { key: "keyword", label: "Instructions (li, add)" },
    { key: "register", label: "Registers (x0, a0)" },
    { key: "directive", label: "Directives (.text)" },
    { key: "number", label: "Numbers (100, 0x10)" },
    { key: "string", label: 'Strings ("...")' },
    { key: "comment", label: "Comments (#)" },
  ];
</script>

<Popover
  bind:open
  title={`Syntax Theme · ${modeStore.mode === "light" ? "Light" : "Dark"}`}
  width="w-72"
>
  <div class="flex flex-col gap-2.5 p-4">
    {#each fields as { key, label } (key)}
      <label
        class="flex items-center justify-between text-[12.5px] text-text-dim"
      >
        <span>{label}</span>
        <input
          type="color"
          class="h-7 w-7 cursor-pointer rounded border border-border bg-transparent p-0"
          bind:value={palette[key]}
        />
      </label>
    {/each}
    <button
      class="mt-1 self-start text-[11px] text-text-faint transition-colors hover:text-text"
      onclick={() => resetActiveTheme()}>↻ Reset to defaults</button
    >
  </div>
</Popover>
