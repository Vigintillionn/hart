<script lang="ts">
  import { displayStore } from "$lib/store/displayStore.svelte";
  import SegmentedControl from "../ui/SegmentedControl.svelte";
  import Toggle from "../ui/Toggle.svelte";
  import SettingRow from "./SettingRow.svelte";
  import SettingsSection from "./SettingsSection.svelte";
</script>

<SettingsSection title="Registers">
  <SettingRow id="display.registerNaming">
    <SegmentedControl
      bind:value={displayStore.registerNaming}
      options={[
        { value: "abi", label: "ABI" },
        { value: "numeric", label: "x0–x31" },
      ]}
    />
  </SettingRow>
</SettingsSection>

<SettingsSection title="Memory">
  <SettingRow id="display.byteWidth">
    <SegmentedControl
      bind:value={displayStore.memBytesPerGroup}
      options={[
        { value: 1, label: "1" },
        { value: 2, label: "2" },
        { value: 4, label: "4" },
        { value: 8, label: "8" },
      ]}
    />
  </SettingRow>

  <SettingRow id="display.endianness">
    <SegmentedControl
      bind:value={displayStore.endianness}
      disabled={displayStore.memBytesPerGroup === 1}
      options={[
        { value: "little", label: "Little" },
        { value: "big", label: "Big" },
      ]}
    />
  </SettingRow>
</SettingsSection>

<SettingsSection title="Highlighting">
  <SettingRow id="display.flashChanges">
    <Toggle bind:checked={displayStore.flashChanges} label="Highlight changes" />
  </SettingRow>
</SettingsSection>
