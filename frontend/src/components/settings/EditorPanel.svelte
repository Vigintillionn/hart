<script lang="ts">
  import {
    darkTheme,
    lightTheme,
    resetActiveTheme,
    type ThemeColors,
  } from "$lib/editor/theme.svelte";
  import { modeStore } from "$lib/store/mode.svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import ColorField from "../ui/ColorField.svelte";
  import SettingRow from "./SettingRow.svelte";
  import SettingsSection from "./SettingsSection.svelte";

  const palette = $derived(modeStore.mode === "light" ? lightTheme : darkTheme);

  const rows: { id: string; key: keyof ThemeColors }[] = [
    { id: "editor.background", key: "background" },
    { id: "editor.keyword", key: "keyword" },
    { id: "editor.register", key: "register" },
    { id: "editor.directive", key: "directive" },
    { id: "editor.number", key: "number" },
    { id: "editor.string", key: "string" },
    { id: "editor.comment", key: "comment" },
  ];
</script>

<SettingsSection
  title={`Syntax colours · ${modeStore.mode === "light" ? "Light" : "Dark"}`}
>
  {#each rows as row (row.id)}
    <SettingRow id={row.id}>
      <ColorField bind:value={palette[row.key]} />
    </SettingRow>
  {/each}

  {#if !settingsStore.q}
    <button
      class="mt-3 text-[11px] text-text-faint transition-colors hover:text-text"
      onclick={() => resetActiveTheme()}
    >
      ↻ Reset to defaults
    </button>
  {/if}
</SettingsSection>
