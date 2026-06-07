<script lang="ts">
  import type { Snippet } from "svelte";
  import { provideSection } from "./section";

  let { title, children }: { title?: string; children: Snippet } = $props();

  const reports = $state<Record<string, boolean>>({});
  provideSection({
    report: (id, visible) => {
      reports[id] = visible;
    },
  });

  const hasRows = $derived(Object.keys(reports).length > 0);
  const anyVisible = $derived(Object.values(reports).some(Boolean));
  const visible = $derived(!hasRows || anyVisible);
</script>

<section class="mb-7 last:mb-0" class:hidden={!visible}>
  {#if title}
    <h3
      class="mb-2 text-[11px] font-semibold uppercase tracking-[1.2px] text-text-faint"
    >
      {title}
    </h3>
  {/if}
  {@render children()}
</section>
