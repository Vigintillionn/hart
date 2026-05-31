<script lang="ts">
  import type { IconName } from "$lib/types";
  import Icon from "../Icon.svelte";

  let {
    name,
    title,
    onclick,
    active = false,
    size = "md",
    iconClass,
  }: {
    name: IconName;
    title: string;
    onclick: () => void;
    active?: boolean;
    size?: "sm" | "md";
    iconClass?: string;
  } = $props();

  const box = $derived(
    size === "sm" ? "h-6.5 w-6.5 rounded-[5px]" : "h-8 w-8 rounded-md",
  );
  const icon = $derived(
    iconClass ?? (size === "sm" ? "h-3.5 w-3.5" : "h-3.75 w-3.75"),
  );
</script>

<button
  class="grid place-items-center transition-colors hover:bg-surface-3 {box} {active
    ? 'text-primary'
    : 'text-text-faint hover:text-text-dim'}"
  {title}
  {onclick}
>
  <Icon {name} class={icon} />
</button>
