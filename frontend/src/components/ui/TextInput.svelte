<script lang="ts">
  import type { IconName } from "$lib/types";
  import Icon from "../Icon.svelte";

  let {
    value = $bindable(""),
    placeholder = "",
    type = "text",
    icon,
    autofocus = false,
    oninput,
    onkeydown,
  }: {
    value?: string;
    placeholder?: string;
    type?: "text" | "search";
    icon?: IconName;
    autofocus?: boolean;
    oninput?: (e: Event) => void;
    onkeydown?: (e: KeyboardEvent) => void;
  } = $props();
</script>

<div class="relative flex items-center">
  {#if icon}
    <Icon
      name={icon}
      class="pointer-events-none absolute left-2.5 h-3.5 w-3.5 text-text-faint"
    />
  {/if}
  <input
    {type}
    {placeholder}
    bind:value
    {oninput}
    {onkeydown}
    class={[
      "w-full rounded-md border border-border bg-surface-0 py-1.5 text-[12.5px] text-text outline-none transition-colors placeholder:text-text-faint focus:border-primary/50",
      icon ? "pl-8 pr-2.5" : "px-2.5",
    ]}
    {@attach (node) => {
      if (autofocus) queueMicrotask(() => node.focus());
    }}
  />
</div>
