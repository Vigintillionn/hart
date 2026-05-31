<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    open = $bindable(),
    title = "",
    width = "w-56",
    children,
  }: {
    open: boolean;
    title?: string;
    width?: string;
    children: Snippet;
  } = $props();
</script>

{#if open}
  <button
    class="fixed inset-0 z-40 cursor-default"
    aria-label="Close menu"
    onclick={() => (open = false)}
  ></button>

  <div
    class="absolute right-0 top-full z-50 mt-1.5 {width} overflow-hidden rounded-lg border border-border-strong bg-surface-2 shadow-2xl"
  >
    {#if title}
      <div
        class="flex items-center justify-between border-b border-border bg-surface-1 px-4 py-3"
      >
        <h3
          class="text-[11px] font-semibold uppercase tracking-[1.5px] text-text-dim"
        >
          {title}
        </h3>
        <button
          class="text-lg leading-none text-text-faint transition-colors hover:text-text"
          aria-label="Close"
          onclick={() => (open = false)}>×</button
        >
      </div>
    {/if}
    {@render children()}
  </div>
{/if}
