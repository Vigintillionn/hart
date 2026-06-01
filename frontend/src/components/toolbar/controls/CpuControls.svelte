<script lang="ts">
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { keymap } from "$lib/keymap.svelte";
  import Icon from "../../Icon.svelte";

  const status = $derived(cpuStore.status);
  const loaded = $derived(cpuStore.isLoaded);
  const dirty = $derived(cpuStore.isDirty);
  const running = $derived(status === "Running");
  const halted = $derived(status === "Halted");
  const atStart = $derived((cpuStore.cpuState?.cycles ?? 0) === 0);

  const primary = $derived.by(() => {
    if (running)
      return {
        label: "Pause",
        icon: "pause" as const,
        run: () => cpuStore.handlePause(),
        keys: keymap.describe("pause"),
      };
    if (halted && !dirty)
      return {
        label: "Restart",
        icon: "rewind" as const,
        run: () => cpuStore.handleRewind(),
        keys: keymap.describe("rewind"),
      };
    return {
      label: "Run",
      icon: "play" as const,
      run: () => cpuStore.handleRun(),
      keys: keymap.describe("run"),
    };
  });
</script>

<div class="flex items-center gap-1">
  <button
    class="relative inline-flex h-8.5 items-center gap-1.5 rounded-md border border-transparent bg-surface-3 px-2.5 text-[12.5px] font-medium text-secondary transition-colors hover:bg-surface-4 disabled:opacity-30"
    title={(dirty
      ? "Source changed since last compile — Run will recompile"
      : "Compile & load the current file") + ` (${keymap.describe("compile")})`}
    disabled={running}
    onclick={() => cpuStore.handleLoadProgram()}
  >
    <Icon name="build" class="h-4 w-4" />
    <span>Compile</span>
    {#if dirty}
      <span
        class="absolute -top-0.5 -right-0.5 h-2 w-2 rounded-full bg-primary shadow-[0_0_0_2px_var(--color-surface-2)]"
        aria-label="modified since last compile"
      ></span>
    {/if}
  </button>

  <button
    class="inline-flex h-8.5 items-center gap-1.5 rounded-md px-3.5 text-[12.5px] font-semibold text-on-primary transition-colors disabled:opacity-30 {running
      ? 'bg-surface-3 text-primary! shadow-[inset_0_0_0_1px_var(--color-primary-soft)]'
      : 'bg-primary hover:bg-primary-hover'}"
    disabled={!loaded}
    title={`${primary.label} (${primary.keys})`}
    onclick={primary.run}
  >
    <Icon name={primary.icon} class="h-3.75 w-3.75" />
    {primary.label}
  </button>

  <button
    class="inline-flex h-8.5 items-center gap-1.5 rounded-md border border-transparent bg-transparent px-2.5 text-[12.5px] font-medium text-text-dim transition-colors hover:bg-surface-3 hover:text-text disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-text-dim"
    title={`Step forward one instruction (${keymap.describe("stepForward")})`}
    disabled={!loaded || halted || running}
    onclick={() => cpuStore.handleStepFwd()}
  >
    <Icon name="stepFwd" class="h-4 w-4" /><span>Step</span>
  </button>

  <button
    class="inline-flex h-8.5 items-center gap-1.5 rounded-md border border-transparent bg-transparent px-2.5 text-[12.5px] font-medium text-text-dim transition-colors hover:bg-surface-3 hover:text-text disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-text-dim"
    title={`Step backward (${keymap.describe("stepBack")})`}
    disabled={!loaded || running || atStart}
    onclick={() => cpuStore.handleStepBack()}
  >
    <Icon name="stepBack" class="h-4 w-4" /><span>Back</span>
  </button>

  <button
    class="group inline-flex h-8.5 items-center gap-1.5 rounded-md border border-transparent bg-transparent px-2.5 text-[12.5px] font-medium text-text-dim transition-colors hover:bg-surface-3 hover:text-red! disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-text-dim!"
    title={`Rewind to entry point (${keymap.describe("rewind")})`}
    disabled={!loaded || running}
    onclick={() => cpuStore.handleRewind()}
  >
    <Icon name="rewind" class="h-4 w-4" /><span>Rewind</span>
  </button>
</div>
