<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Editor from "../components/Editor.svelte";
  import Header from "../components/Header.svelte";
  import StyleSettings from "../components/StyleSettings.svelte";
  import TerminalContainer from "../components/TerminalContainer.svelte";
  import DebugPanel from "../components/DebugPanel.svelte";
  import { cpuStore } from "$lib/cpuStore.svelte";

  let showSettings = $state(false);

  onMount(() => {
    cpuStore.initListener();
  });

  onDestroy(() => {
    cpuStore.cleanup();
  });
</script>

<div
  class="flex flex-col h-screen w-screen relative bg-zinc-950 text-zinc-300 font-sans overflow-hidden"
>
  <Header bind:showSettings />
  {#if showSettings}
    <StyleSettings bind:showSettings />
  {/if}

  <main class="flex flex-1 overflow-hidden">
    <section
      class="flex flex-col flex-2 min-w-0 bg-zinc-900 border-r border-zinc-800"
    >
      <Editor />
    </section>

    <aside class="flex flex-col flex-1 min-w-75 bg-zinc-900">
      <DebugPanel />
    </aside>
  </main>

  <footer
    class="flex flex-col h-[30%] min-h-50 bg-zinc-900 border-t border-zinc-800"
  >
    <TerminalContainer />
  </footer>
</div>
