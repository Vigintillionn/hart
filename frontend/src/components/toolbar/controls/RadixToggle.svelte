<script lang="ts">
  import { layoutStore } from "$lib/store/layoutStore.svelte";
  import SegmentedControl from "../../ui/SegmentedControl.svelte";
</script>

<SegmentedControl
  bind:value={layoutStore.hexMode}
  options={[
    { value: true, label: "HEX" },
    { value: false, label: "DEC" },
  ]}
/>
