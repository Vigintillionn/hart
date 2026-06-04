<script lang="ts">
  import { modeStore } from "$lib/store/mode.svelte";
  import SegmentedControl from "../ui/SegmentedControl.svelte";
  import SettingRow from "./SettingRow.svelte";
  import SettingsSection from "./SettingsSection.svelte";
</script>

<SettingsSection title="Appearance">
  <SettingRow id="appearance.mode">
    <SegmentedControl
      bind:value={modeStore.preference}
      options={[
        { value: "system", label: "System" },
        { value: "light", label: "Light" },
        { value: "dark", label: "Dark" },
      ]}
    />
  </SettingRow>
</SettingsSection>
