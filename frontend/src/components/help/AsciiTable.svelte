<script lang="ts">
  import type { AsciiInfo } from "$lib/store/helpCatalogue.svelte";
  import ReferenceTable from "./ReferenceTable.svelte";

  let { items }: { items: AsciiInfo[] } = $props();

  const half = $derived(Math.ceil(items.length / 2));
  const col1 = $derived(items.slice(0, half));
  const col2 = $derived(items.slice(half));
</script>

<section class="mb-7 last:mb-0">
  <div class="mb-1 flex items-center gap-2">
    <h3 class="text-[12.5px] font-semibold text-text">ASCII Table</h3>
  </div>
  <p class="mb-4 text-[11px] leading-snug text-text-dim">
    Standard 7-bit ASCII character encoding reference.
  </p>

  <div class="grid grid-cols-2 gap-x-8">
    {#if col1.length}
      <ReferenceTable columns={["Dec", "Hex", "Char", "Description"]}>
        {#each col1 as entry (entry.dec)}
          {@render asciiRow(entry)}
        {/each}
      </ReferenceTable>
    {/if}

    {#if col2.length}
      <ReferenceTable columns={["Dec", "Hex", "Char", "Description"]}>
        {#each col2 as entry (entry.dec)}
          {@render asciiRow(entry)}
        {/each}
      </ReferenceTable>
    {/if}
  </div>
</section>

{#snippet asciiRow(entry: AsciiInfo)}
  <tr class="border-b border-border-soft align-top last:border-0">
    <td
      class="whitespace-nowrap py-2 pr-4 font-mono text-[11.5px] text-text-dim"
    >
      {entry.dec}
    </td>
    <td
      class="whitespace-nowrap py-2 pr-4 font-mono text-[11.5px] text-text-dim"
    >
      0x{entry.hex}
    </td>
    <td class="whitespace-nowrap py-2 pr-4 font-mono text-[12px]">
      {#if entry.isControl}
        <span
          class="rounded bg-control px-1 py-px text-[10px] font-semibold uppercase tracking-wide text-text-faint"
        >
          {entry.char}
        </span>
      {:else}
        <span class="font-semibold text-primary">{entry.char}</span>
      {/if}
    </td>
    <td class="py-2 text-[11.5px] leading-snug text-text-dim">
      {entry.desc}
    </td>
  </tr>
{/snippet}
