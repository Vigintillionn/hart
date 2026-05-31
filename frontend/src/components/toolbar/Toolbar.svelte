<script lang="ts">
  import Logo from "../Logo.svelte";
  import StatusPill from "../debug/StatusPill.svelte";
  import CpuControls from "./controls/CpuControls.svelte";
  import Controls from "./controls/Controls.svelte";
  import RadixToggle from "./controls/RadixToggle.svelte";
</script>

<div
  class="flex h-13 flex-none items-center gap-4 border-b border-border bg-surface-2 pl-4 pr-3.5"
>
  <Logo />
  <div class="h-5.5 w-px bg-border"></div>
  <CpuControls />
  <div class="flex-1"></div>
  <Controls />
  <div class="h-5.5 w-px bg-border"></div>
  <StatusPill />
  <RadixToggle />
</div>
