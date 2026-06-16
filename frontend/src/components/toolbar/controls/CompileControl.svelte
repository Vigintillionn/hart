<script lang="ts">
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { buildStore, type BuildMode } from "$lib/store/buildStore.svelte";
  import { keymap } from "$lib/keymap.svelte";
  import Icon from "../../Icon.svelte";
  import Popover from "../../ui/Popover.svelte";
  import SegmentedControl from "../../ui/SegmentedControl.svelte";

  let { disabled = false }: { disabled?: boolean } = $props();

  const dirty = $derived(cpuStore.isDirty);
  const buildCount = $derived(buildStore.resolveBuildFiles().length);
  const activeId = $derived(fileStore.activeFileId);

  let menuOpen = $state(false);

  const modeOptions: { value: BuildMode; label: string }[] = [
    { value: "single", label: "Single" },
    { value: "all", label: "All" },
    { value: "select", label: "Select" },
  ];

  const tip = $derived(
    (dirty
      ? "Source changed since last compile - Run will recompile"
      : "Compile & load") + ` (${keymap.describe("compile")})`,
  );

  function compile() {
    menuOpen = false;
    cpuStore.handleLoadProgram();
  }
</script>

<div class="relative flex items-stretch">
  <button
    class="relative inline-flex h-8.5 items-center gap-1.5 rounded-l-md bg-surface-3 pl-2.5 pr-2 text-[12.5px] font-medium text-secondary transition-colors hover:bg-surface-4 disabled:opacity-30"
    title={tip}
    {disabled}
    onclick={compile}
  >
    <Icon name="build" class="h-4 w-4" />
    <span>Compile</span>
    {#if buildCount > 1}
      <span
        class="ml-0.5 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-surface-1 px-1 font-mono text-[10px] text-text-dim"
        title="{buildCount} files in this build"
      >
        {buildCount}
      </span>
    {/if}
  </button>

  <button
    class="inline-flex h-8.5 items-center rounded-r-md border-l border-surface-1 bg-surface-3 px-1.5 text-secondary transition-colors hover:bg-surface-4 disabled:opacity-30 {menuOpen
      ? 'bg-surface-4'
      : ''}"
    title="Build options"
    aria-label="Build options"
    aria-expanded={menuOpen}
    {disabled}
    onclick={() => (menuOpen = !menuOpen)}
  >
    <Icon
      name="chevron"
      class="h-3 w-3 transition-transform {menuOpen ? 'rotate-180' : ''}"
    />
  </button>

  {#if dirty}
    <span
      class="pointer-events-none absolute -top-0.5 -right-0.5 h-2 w-2 rounded-full bg-primary shadow-[0_0_0_2px_var(--color-surface-2)]"
      aria-label="modified since last compile"
    ></span>
  {/if}

  <Popover bind:open={menuOpen} title="Build" width="w-64" align="left">
    <div class="space-y-3 p-3.5">
      <div class="space-y-1.5">
        <div
          class="text-[10.5px] font-semibold uppercase tracking-[1px] text-text-faint"
        >
          Assemble
        </div>
        <SegmentedControl options={modeOptions} bind:value={buildStore.mode} />
      </div>

      {#if buildStore.mode === "select"}
        <div class="space-y-0.5">
          {#each fileStore.openFiles as file (file.id)}
            {@const isEntry = file.id === activeId}
            <label
              class="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-[12px] transition-colors hover:bg-surface-3 {isEntry
                ? 'cursor-default'
                : ''}"
            >
              <input
                type="checkbox"
                class="h-3.5 w-3.5 accent-primary disabled:opacity-60"
                checked={buildStore.isIncluded(file.id)}
                disabled={isEntry}
                onchange={() => buildStore.toggle(file.id)}
              />
              <span class="flex-1 truncate font-mono text-text-dim"
                >{file.name}</span
              >
              {#if isEntry}
                <span
                  class="rounded-sm bg-primary-soft px-1.5 py-0.5 font-mono text-[9.5px] uppercase tracking-[0.5px] text-primary"
                  >entry</span
                >
              {/if}
            </label>
          {/each}
        </div>
      {/if}

      <p class="text-[11px] leading-relaxed text-text-faint">
        The active file is the entry point (address 0); the rest link after it.
      </p>
    </div>
  </Popover>
</div>
