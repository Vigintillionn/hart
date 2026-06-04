<script lang="ts">
  import type { Snippet } from "svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";

  let { id, children }: { id: string; children: Snippet } = $props();

  const descriptor = $derived(settingsStore.descriptor(id));
  const visible = $derived(settingsStore.matchesId(id));
</script>

{#if visible && descriptor}
  <div
    class="flex items-center justify-between gap-6 border-b border-border-soft py-3 last:border-0"
  >
    <div class="min-w-0">
      <div class="text-[13px] font-medium text-text">{descriptor.title}</div>
      {#if descriptor.description}
        <div class="mt-0.5 text-[11.5px] leading-snug text-text-dim">
          {descriptor.description}
        </div>
      {/if}
    </div>
    <div class="flex-none">
      {@render children()}
    </div>
  </div>
{/if}
