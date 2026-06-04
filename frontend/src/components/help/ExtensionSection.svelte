<script lang="ts">
  import type { ExtSection } from "$lib/store/helpCatalogue.svelte";
  import ExtBadge from "./ExtBadge.svelte";
  import FormatTable from "./FormatTable.svelte";

  let { section }: { section: ExtSection } = $props();
</script>

<section class="mb-7 last:mb-0">
  <div class="mb-3 flex items-center gap-2">
    <ExtBadge code={section.code} enabled={section.enabled} />
    <h3 class="text-[12.5px] font-semibold text-text">{section.name}</h3>
    {#if !section.enabled}
      <span
        class="rounded bg-control px-1.5 py-0.5 text-[10px] text-text-faint"
      >
        disabled
      </span>
    {/if}
  </div>

  {#each section.fmtGroups as group (group.fmt.id)}
    <FormatTable fmt={group.fmt} items={group.items} dim={!section.enabled} />
  {/each}
</section>
