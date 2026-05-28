<script lang="ts">
  import { toHex } from "$lib/util";

  interface Props {
    pc: number;
    cycles: number;
  }

  let { pc, cycles }: Props = $props();

  let pcShowHex = $state(true);

  const formatPc = (num: number) => (pcShowHex ? toHex(num) : num.toString());
</script>

<div
  class="flex justify-between bg-zinc-950 p-3 rounded-lg border border-zinc-800 mb-4 shadow-inner"
>
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="flex flex-col cursor-pointer select-none"
    onclick={() => (pcShowHex = !pcShowHex)}
    title="Click to toggle Hex/Dec"
  >
    <span class="text-xs text-zinc-500 uppercase tracking-wide">PC</span>
    <strong class="text-lg text-amber-200 font-mono">{formatPc(pc)}</strong>
  </div>
  <div class="flex flex-col text-right">
    <span class="text-xs text-zinc-500 uppercase tracking-wide">Cycles</span>
    <strong class="text-lg text-amber-200 font-mono">{cycles}</strong>
  </div>
</div>
