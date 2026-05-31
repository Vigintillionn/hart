<script lang="ts">
  import { themeColors } from "$lib/editor/theme.svelte";
  import Popover from "../../ui/Popover.svelte";

  let { open = $bindable() }: { open: boolean } = $props();

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

<Popover bind:open title="Syntax Theme" width="w-72">
  <div class="flex flex-col gap-2.5 p-4">
    {#each fields as { key, label } (key)}
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
</Popover>
