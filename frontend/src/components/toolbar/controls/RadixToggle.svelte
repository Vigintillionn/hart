<script lang="ts">
  import SegmentedControl from "../../ui/SegmentedControl.svelte";
  import { displayStore } from "$lib/store/displayStore.svelte";
</script>

<SegmentedControl
  bind:value={displayStore.hexMode}
  options={[
    { value: true, label: "HEX" },
    { value: false, label: "DEC" },
  ]}
/>
