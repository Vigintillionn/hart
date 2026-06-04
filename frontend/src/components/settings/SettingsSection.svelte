<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    title,
    children,
  }: { title?: string; children: Snippet } = $props();
</script>

<section class="mb-7 last:mb-0">
  {#if title}
    <h3
      class="mb-2 text-[11px] font-semibold uppercase tracking-[1.2px] text-text-faint"
    >
      {title}
    </h3>
  {/if}
  {@render children()}
</section>
