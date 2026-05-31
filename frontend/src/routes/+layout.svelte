<script lang="ts">
  import type { Snippet } from "svelte";
  import "@fontsource/geist-sans/300.css";
  import "@fontsource/geist-sans/400.css";
  import "@fontsource/geist-sans/500.css";
  import "@fontsource/geist-sans/600.css";
  import "@fontsource/geist-sans/700.css";
  import "@fontsource/jetbrains-mono/400.css";
  import "@fontsource/jetbrains-mono/500.css";
  import "@fontsource/jetbrains-mono/600.css";
  import "@fontsource/jetbrains-mono/700.css";
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
