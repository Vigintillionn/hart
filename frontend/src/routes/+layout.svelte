<script lang="ts">
  import type { Snippet } from "svelte";
  import "@fontsource-variable/geist";
  import "@fontsource-variable/jetbrains-mono";
  import "../app.css";
  import Titlebar from "../components/Titlebar.svelte";
  let { children }: { children: Snippet } = $props();
</script>

<div
  class="flex h-screen w-screen flex-col overflow-hidden bg-surface-1 text-text"
>
  <Titlebar />
  {@render children()}
</div>
