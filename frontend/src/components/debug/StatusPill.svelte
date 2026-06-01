<script lang="ts">
  import { cpuStore } from "$lib/store/cpuStore.svelte";

  const info = $derived.by(() => {
    if (!cpuStore.isLoaded) return { label: "Ready", cls: "halt" };
    switch (cpuStore.status) {
      case "Running":
        return { label: "Running", cls: "live" };
      case "Halted":
        return { label: "Halted", cls: "halt" };
      case "WaitingForInput":
        return { label: "Waiting for input", cls: "paused" };
      default:
        return { label: "Paused", cls: "paused" };
    }
  });

  const tone: Record<string, string> = {
    live: "before:animate-pulse before:bg-secondary before:shadow-[0_0_8px_var(--secondary-glow)]",
    paused:
      "before:animate-pulse before:bg-primary before:shadow-[0_0_8px_var(--primary-glow)]",
    halt: "before:bg-text-faint",
  };
</script>

<span
  class="inline-flex items-center gap-2 rounded-full border border-border bg-surface-0 px-2.5 py-1.25 font-mono text-[11px] text-text-dim before:h-1.75 before:w-1.75 before:rounded-full before:content-[''] {tone[
    info.cls
  ]}"
>
  {info.label}
</span>
