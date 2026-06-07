<script lang="ts">
  import { extensionStore } from "$lib/store/extensionStore.svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import Icon from "../Icon.svelte";
  import Toggle from "../ui/Toggle.svelte";
  import SettingsSection from "./SettingsSection.svelte";

  const list = $derived(
    extensionStore.catalogue.filter(
      (e) =>
        !settingsStore.q ||
        `${e.code} ${e.name} ${e.summary}`
          .toLowerCase()
          .includes(settingsStore.q),
    ),
  );
</script>

<SettingsSection title="ISA Extensions">
  <div
    class="grid grid-cols-[auto_minmax(0,1fr)_auto] [&>*:nth-last-child(-n+3)]:border-b-0"
  >
    {#each list as ext (ext.code)}
      <div class="border-b border-border-soft py-3 pr-3">
        <span
          class={[
            "mt-0.5 flex h-6 min-w-6 items-center justify-center rounded border px-1 font-semibold",
            ext.code.length > 1 ? "text-[10px]" : "text-[12px]",
            ext.enabled
              ? "border-primary/40 bg-primary-soft text-primary"
              : "border-border text-text-faint",
          ]}
        >
          {ext.code}
        </span>
      </div>

      <div class="min-w-0 border-b border-border-soft py-3">
        <div class="flex items-center gap-1.5">
          <span class="text-[13px] font-medium text-text">{ext.name}</span>
          {#if ext.mandatory}
            <Icon name="lock" class="h-3 w-3 text-text-faint" />
          {/if}
        </div>
        <p class="mt-0.5 text-[11.5px] leading-snug text-text-dim">
          {ext.summary}
        </p>
      </div>

      <div class="flex justify-end border-b border-border-soft py-3 pl-3">
        <div class="mt-0.5">
          <Toggle
            checked={ext.enabled}
            disabled={ext.mandatory}
            label={ext.name}
            onchange={() => extensionStore.toggle(ext.code)}
          />
        </div>
      </div>
    {/each}
  </div>

  {#if extensionStore.catalogue.length === 0}
    <p class="py-2 text-[11.5px] text-text-faint">
      No optional extensions available.
    </p>
  {:else if list.length === 0}
    <p class="py-2 text-[11.5px] text-text-faint">
      No extensions match “{settingsStore.query}”.
    </p>
  {/if}

  <p class="mt-3 text-[11px] leading-snug text-text-faint">
    Changes take effect the next time you build.
  </p>
</SettingsSection>
