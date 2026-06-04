<script lang="ts">
  import { helpStore } from "$lib/store/helpStore.svelte";
  import ExtBadge from "./ExtBadge.svelte";

  type Props = {
    id: string;
    label: string;
    badge?: string | null;
    enabled?: boolean | null;
  };
  let { id, label, badge = null, enabled = null }: Props = $props();

  const active = $derived(helpStore.group === id);
</script>

<button
  onclick={() => helpStore.select(id)}
  class={[
    "flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-left text-[12.5px] transition-colors",
    active
      ? "bg-control text-text"
      : "text-text-dim hover:bg-control/60 hover:text-text",
  ]}
>
  {#if badge}
    <ExtBadge code={badge} enabled={enabled ?? true} />
  {:else}
    <span
      class={[
        "h-1.5 w-1.5 flex-none rounded-full",
        active ? "bg-primary" : "bg-text-faint",
      ]}
    ></span>
  {/if}
  <span class="truncate">{label}</span>
</button>
