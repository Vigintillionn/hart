<script lang="ts">
  import { themeColors } from "$lib/theme.svelte";

  interface Props {
    showSettings: boolean;
  }

  let { showSettings = $bindable() }: Props = $props();
</script>

<div
  class="absolute top-15 right-5 w-72 bg-zinc-900 border border-zinc-800 rounded-lg shadow-xl z-50 flex flex-col overflow-hidden"
>
  <div
    class="flex justify-between items-center px-4 py-3 bg-zinc-950 border-b border-zinc-800"
  >
    <h3 class="m-0 text-sm font-semibold text-white">Theme Colors</h3>
    <button
      class="bg-transparent border-none text-zinc-400 hover:text-white text-xl leading-none cursor-pointer p-0 m-0"
      onclick={() => (showSettings = false)}>×</button
    >
  </div>
  <div class="flex flex-col gap-3 p-4">
    <label class="flex justify-between items-center text-zinc-300 text-sm">
      <span>Background</span>
      <input
        type="color"
        class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
        bind:value={themeColors.background}
      />
    </label>
    <label class="flex justify-between items-center text-zinc-300 text-sm">
      <span>Keywords (li, add)</span>
      <input
        type="color"
        class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
        bind:value={themeColors.keyword}
      />
    </label>
    <label class="flex justify-between items-center text-zinc-300 text-sm">
      <span>Registers (x0, a0)</span>
      <input
        type="color"
        class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
        bind:value={themeColors.register}
      />
    </label>
    <label class="flex justify-between items-center text-zinc-300 text-sm">
      <span>Directives (.text)</span>
      <input
        type="color"
        class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
        bind:value={themeColors.directive}
      />
    </label>
    <label class="flex justify-between items-center text-zinc-300 text-sm">
      <span>Numbers (100, 0x10)</span>
      <input
        type="color"
        class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
        bind:value={themeColors.number}
      />
    </label>
    <label class="flex justify-between items-center text-zinc-300 text-sm">
      <span>Strings ("...")</span>
      <input
        type="color"
        class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
        bind:value={themeColors.string}
      />
    </label>
    <label class="flex justify-between items-center text-zinc-300 text-sm">
      <span>Comments (#)</span>
      <input
        type="color"
        class="w-8 h-8 p-0 cursor-pointer rounded border border-zinc-700 bg-transparent"
        bind:value={themeColors.comment}
      />
    </label>
  </div>
</div>
