<script lang="ts">
  import Icon from "../Icon.svelte";

  let {
    value = $bindable(""),
    options,
    previewFont = false,
  }: {
    value?: string;
    options: { value: string; label: string }[];
    previewFont?: boolean;
  } = $props();

  let open = $state(false);
  let trigger = $state<HTMLButtonElement>();
  let rect = $state<DOMRect | null>(null);

  const selected = $derived(
    options.find((o) => o.value === value) ?? options[0],
  );

  const fontOf = (v: string) =>
    !previewFont
      ? undefined
      : v === "monospace"
        ? "monospace"
        : `'${v}', monospace`;

  function place() {
    if (trigger) rect = trigger.getBoundingClientRect();
  }

  function toggle() {
    if (!open) place();
    open = !open;
  }

  function choose(v: string) {
    value = v;
    open = false;
  }

  function onWindowKeydown(e: KeyboardEvent) {
    if (open && e.key === "Escape") {
      e.preventDefault();
      open = false;
    }
  }
</script>

<svelte:window
  onkeydown={onWindowKeydown}
  onresizecapture={() => (open = false)}
  onscrollcapture={() => (open = false)}
/>

<button
  bind:this={trigger}
  type="button"
  onclick={toggle}
  aria-haspopup="listbox"
  aria-expanded={open}
  class="flex min-w-40 items-center justify-between gap-2 rounded-md border border-border bg-surface-3 py-1.5 pl-2.5 pr-2 font-mono text-[11.5px] text-text outline-none transition-colors hover:border-primary-soft"
  style:font-family={fontOf(value)}
>
  <span class="truncate">{selected?.label}</span>
  <Icon name="chevron" class="h-3.5 w-3.5 flex-none text-text-faint" />
</button>

{#if open && rect}
  <button
    class="fixed inset-0 z-105 cursor-default"
    aria-label="Close menu"
    onclick={() => (open = false)}
  ></button>

  <div
    role="listbox"
    class="scroll-thin fixed z-110 max-h-64 overflow-y-auto rounded-lg border border-border-strong bg-surface-2 p-1 shadow-2xl"
    style:top="{rect.bottom + 4}px"
    style:left="{rect.left}px"
    style:min-width="{rect.width}px"
  >
    {#each options as opt (opt.value)}
      <button
        type="button"
        role="option"
        aria-selected={opt.value === value}
        onclick={() => choose(opt.value)}
        class={[
          "flex w-full items-center justify-between gap-3 rounded-md px-2.5 py-1.5 text-left font-mono text-[11.5px] transition-colors",
          opt.value === value
            ? "bg-control text-text"
            : "text-text-dim hover:bg-control/60 hover:text-text",
        ]}
        style:font-family={fontOf(opt.value)}
      >
        <span class="truncate">{opt.label}</span>
        {#if opt.value === value}
          <Icon name="check" class="h-3.5 w-3.5 flex-none text-primary" />
        {/if}
      </button>
    {/each}
  </div>
{/if}
