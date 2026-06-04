<script lang="ts">
  import { helpStore } from "$lib/store/helpStore.svelte";
  import Icon from "../Icon.svelte";
  import HelpSidebar from "./HelpSidebar.svelte";
  import HelpContent from "./HelpContent.svelte";

  function onKeydown(e: KeyboardEvent) {
    if (helpStore.open && e.key === "Escape") {
      e.preventDefault();
      helpStore.close();
    }
  }
</script>

<svelte:window onkeydown={onKeydown} />

{#if helpStore.open}
  <div class="fixed inset-0 z-100 flex items-center justify-center">
    <button
      class="absolute inset-0 cursor-default bg-black/50"
      aria-label="Close reference"
      onclick={() => helpStore.close()}
    ></button>

    <div
      class="relative flex h-[78vh] max-h-160 w-220 max-w-[92vw] overflow-hidden rounded-xl border border-border-strong bg-surface-2 shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-label="RISC-V reference"
    >
      <HelpSidebar />

      <div class="flex min-w-0 flex-1 flex-col">
        <header
          class="flex flex-none items-center justify-between border-b border-border px-5 py-3"
        >
          <h2
            class="flex items-center gap-2 text-[13px] font-semibold text-text"
          >
            <Icon name="book" class="h-4 w-4 text-text-faint" />
            RISC-V reference
          </h2>
          <button
            class="grid h-7 w-7 place-items-center rounded-md text-text-faint transition-colors hover:bg-surface-3 hover:text-text"
            aria-label="Close"
            onclick={() => helpStore.close()}
          >
            <Icon name="close" class="h-4 w-4" />
          </button>
        </header>

        <HelpContent />
      </div>
    </div>
  </div>
{/if}
