<script lang="ts">
  import {
    darkTheme,
    lightTheme,
    resetActiveTheme,
    type ThemeColors,
  } from "$lib/editor/theme.svelte";
  import { modeStore } from "$lib/store/mode.svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import {
    editorPrefs,
    FONT_FAMILIES,
    FONT_SIZES,
  } from "$lib/store/editorPrefs.svelte";
  import ColorField from "../ui/ColorField.svelte";
  import SegmentedControl from "../ui/SegmentedControl.svelte";
  import Select from "../ui/Select.svelte";
  import Toggle from "../ui/Toggle.svelte";
  import SettingRow from "./SettingRow.svelte";
  import SettingsSection from "./SettingsSection.svelte";

  const palette = $derived(modeStore.mode === "light" ? lightTheme : darkTheme);

  const allHover = $derived(
    editorPrefs.hoverInstructions &&
      editorPrefs.hoverDirectives &&
      editorPrefs.hoverRegisters,
  );
  function setAllHover(v: boolean) {
    editorPrefs.hoverInstructions = v;
    editorPrefs.hoverDirectives = v;
    editorPrefs.hoverRegisters = v;
  }

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

<SettingsSection title="Editor">
  <SettingRow id="editor.fontFamily">
    <Select
      bind:value={editorPrefs.fontFamily}
      previewFont
      options={FONT_FAMILIES.map((f) => ({ value: f, label: f }))}
    />
  </SettingRow>

  <SettingRow id="editor.fontSize">
    <SegmentedControl
      bind:value={editorPrefs.fontSize}
      options={FONT_SIZES.map((s) => ({ value: s, label: String(s) }))}
    />
  </SettingRow>

  <SettingRow id="editor.tabWidth">
    <SegmentedControl
      bind:value={editorPrefs.tabWidth}
      options={[
        { value: 2, label: "2" },
        { value: 4, label: "4" },
        { value: 8, label: "8" },
      ]}
    />
  </SettingRow>

  <SettingRow id="editor.indentStyle">
    <SegmentedControl
      bind:value={editorPrefs.insertSpaces}
      options={[
        { value: true, label: "Spaces" },
        { value: false, label: "Tabs" },
      ]}
    />
  </SettingRow>

  <SettingRow id="editor.lineNumbers">
    <SegmentedControl
      bind:value={editorPrefs.lineNumbers}
      options={[
        { value: "on", label: "Absolute" },
        { value: "relative", label: "Relative" },
        { value: "off", label: "Off" },
      ]}
    />
  </SettingRow>

  <SettingRow id="editor.wordWrap">
    <Toggle bind:checked={editorPrefs.wordWrap} label="Word wrap" />
  </SettingRow>

  <SettingRow id="editor.whitespace">
    <Toggle
      bind:checked={editorPrefs.renderWhitespace}
      label="Show whitespace"
    />
  </SettingRow>

  <SettingRow id="editor.minimap">
    <Toggle bind:checked={editorPrefs.minimap} label="Minimap" />
  </SettingRow>
</SettingsSection>

<SettingsSection title="Editor hover">
  <SettingRow id="editor.hover">
    <Toggle checked={allHover} onchange={setAllHover} label="All hover docs" />
  </SettingRow>

  <SettingRow id="editor.hoverInstructions">
    <Toggle
      bind:checked={editorPrefs.hoverInstructions}
      label="Instruction hover"
    />
  </SettingRow>

  <SettingRow id="editor.hoverDirectives">
    <Toggle
      bind:checked={editorPrefs.hoverDirectives}
      label="Directive hover"
    />
  </SettingRow>

  <SettingRow id="editor.hoverRegisters">
    <Toggle
      bind:checked={editorPrefs.hoverRegisters}
      label="Register hover"
    />
  </SettingRow>
</SettingsSection>

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
