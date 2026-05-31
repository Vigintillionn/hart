<script>
  import "../app.css";
  import Titlebar from "../components/Titlebar.svelte";
  let { children } = $props();
</script>

<div
  class="flex h-screen w-screen flex-col overflow-hidden bg-surface-1 text-text"
>
  <Titlebar />
  {@render children()}
</div>
