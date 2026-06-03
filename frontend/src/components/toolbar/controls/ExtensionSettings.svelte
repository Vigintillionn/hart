<script lang="ts">
  import { extensionStore } from "$lib/store/extensionStore.svelte";
  import Icon from "../../Icon.svelte";
  import Popover from "../../ui/Popover.svelte";

  let { open = $bindable() }: { open: boolean } = $props();
</script>

<Popover bind:open title="ISA Extensions" width="w-80">
  <div class="flex flex-col gap-0.5 p-2">
    {#each extensionStore.catalogue as ext (ext.code)}
      <button
        type="button"
        class="flex items-start gap-3 rounded-md p-2 text-left transition-colors
          {ext.mandatory
          ? 'cursor-default'
          : 'cursor-pointer hover:bg-surface-1'}"
        disabled={ext.mandatory}
        role="switch"
        aria-checked={ext.enabled}
        aria-label={ext.name}
        onclick={() => extensionStore.toggle(ext.code)}
      >
        <span
          class="mt-0.5 flex h-6 w-6 flex-none items-center justify-center rounded
            border text-[12px] font-semibold transition-colors
            {ext.enabled
            ? 'border-primary/40 bg-primary-soft text-primary'
            : 'border-border text-text-faint'}"
        >
          {ext.code}
        </span>

        <span class="flex-1">
          <span class="flex items-center gap-1.5">
            <span class="text-[13px] font-medium text-text">{ext.name}</span>
            {#if ext.mandatory}
              <Icon name="lock" class="h-3 w-3 text-text-faint" />
            {/if}
          </span>
          <span class="mt-0.5 block text-[11.5px] leading-snug text-text-dim">
            {ext.summary}
          </span>
        </span>

        <span
          class="relative mt-1 h-5 w-9 flex-none rounded-full transition-colors
            {ext.enabled ? 'bg-primary-soft' : 'bg-border-strong'}
            {ext.mandatory ? 'opacity-50' : ''}"
        >
          <span
            class="absolute left-0.5 top-0.5 h-4 w-4 rounded-full shadow-sm
              transition-transform duration-150
              {ext.enabled
              ? 'translate-x-4 bg-primary'
              : 'translate-x-0 bg-text-faint'}"
          ></span>
        </span>
      </button>
    {/each}

    {#if !extensionStore.hasOptional}
      <p class="px-2 py-1 text-[11.5px] text-text-faint">
        No optional extensions available.
      </p>
    {/if}
  </div>

  <p
    class="border-t border-border px-3.5 py-2 text-[11px] leading-snug text-text-faint"
  >
    Changes take effect the next time you build.
  </p>
</Popover>
