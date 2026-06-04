<script lang="ts">
  import { terminalStore } from "$lib/store/terminalStore.svelte";
  import Toggle from "../ui/Toggle.svelte";
  import SettingRow from "./SettingRow.svelte";
  import SettingsSection from "./SettingsSection.svelte";
</script>

<SettingsSection title="Terminal">
  <SettingRow id="terminal.clearOnRun">
    <Toggle
      bind:checked={terminalStore.clearOnRun}
      label="Clear program console on run"
    />
  </SettingRow>

  <SettingRow id="terminal.autoSwitch">
    <Toggle
      bind:checked={terminalStore.autoSwitchTabs}
      label="Auto-switch console tabs"
    />
  </SettingRow>
</SettingsSection>
