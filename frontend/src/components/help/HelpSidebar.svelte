<script lang="ts">
  import { helpStore } from "$lib/store/helpStore.svelte";
  import { helpCatalogue } from "$lib/store/helpCatalogue.svelte";
  import TextInput from "../ui/TextInput.svelte";
  import HelpNavItem from "./HelpNavItem.svelte";
  import ScrollArea from "../ui/ScrollArea.svelte";
</script>

<aside class="flex w-56 flex-none flex-col border-r border-border bg-surface-1">
  <div class="border-b border-border p-3">
    <TextInput
      icon="search"
      type="search"
      placeholder="Search reference"
      bind:value={helpStore.query}
      autofocus
    />
  </div>
  <ScrollArea
    class="min-h-0 flex-1"
    viewportClass="h-full p-2"
    role="navigation"
  >
    <HelpNavItem id="all" label="Everything" />

    {@render heading("Extensions")}
    {#each helpCatalogue.extGroups as g (g.code)}
      <HelpNavItem
        id={g.code}
        label={g.name}
        badge={g.code}
        enabled={g.enabled}
      />
    {/each}

    {@render heading("Assembler")}
    <HelpNavItem id="pseudo" label="Pseudo-instructions" />
    <HelpNavItem id="directives" label="Directives" />

    {@render heading("Runtime")}
    <HelpNavItem id="syscall" label="System calls" />
    <HelpNavItem id="csrs" label="Control &amp; status registers" />

    {@render heading("Other")}
    <HelpNavItem id="registers" label="Calling conventions" />
    <HelpNavItem id="ascii" label="ASCII Table" />

    {@render heading("Tools")}
    <HelpNavItem id="converter" label="Number converter" />
  </ScrollArea>

  <div class="flex-none border-t border-border px-3 py-3">
    <p
      class="pb-1.5 text-[10px] font-semibold uppercase tracking-[1.1px] text-text-faint"
    >
      Notation
    </p>
    <div class="flex flex-col gap-1 text-[11px] text-text-dim">
      {@render notation("xᵤ", "unsigned operand/operator")}
      {@render notation("xₛ", "signed operand/operator")}
    </div>
  </div>
</aside>

{#snippet heading(label: string)}
  <p
    class="px-2.5 pb-1 pt-3 text-[10px] font-semibold uppercase tracking-[1.1px] text-text-faint"
  >
    {label}
  </p>
{/snippet}

{#snippet notation(symbol: string, meaning: string)}
  <span class="flex items-baseline gap-2">
    <code class="font-mono text-[12px] text-text">{symbol}</code>
    {meaning}
  </span>
{/snippet}
