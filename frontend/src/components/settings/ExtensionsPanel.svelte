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
  {#each list as ext (ext.code)}
    <div
      class="flex items-start gap-3 border-b border-border-soft py-3 last:border-0"
    >
      <span
        class={[
          "mt-0.5 flex h-6 w-6 flex-none items-center justify-center rounded border text-[12px] font-semibold",
          ext.enabled
            ? "border-primary/40 bg-primary-soft text-primary"
            : "border-border text-text-faint",
        ]}
      >
        {ext.code}
      </span>

      <div class="min-w-0 flex-1">
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
