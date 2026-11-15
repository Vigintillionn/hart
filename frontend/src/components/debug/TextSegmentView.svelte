<script lang="ts">
  import { untrack } from "svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { toHex, bin32 } from "$lib/util";
  import { displayStore } from "$lib/store/displayStore.svelte";
  import ScrollArea from "../ui/ScrollArea.svelte";

  const rows = $derived(cpuStore.textRowsDisplay);
  const pc = $derived(cpuStore.cpuState?.pc ?? -1);

  const COLS =
    "grid grid-cols-[1.5rem_6.5rem_var(--code-w)_13rem_auto] items-center gap-x-3";

  let showBinary = $state(false);

  let scroller: HTMLElement | undefined = $state();

  let flashAddr = $state<number | null>(null);
  let prevPc: number | undefined;
  let timer: number;
  $effect(() => {
    const cur = pc;
    untrack(() => {
      if (prevPc !== undefined && cur !== prevPc && cur >= 0) {
        flashAddr = cur;
        clearTimeout(timer);
        timer = window.setTimeout(() => (flashAddr = null), 680);
        scroller
          ?.querySelector(`[data-addr="${cur}"]`)
          ?.scrollIntoView({ block: "nearest" });
      }
      prevPc = cur;
    });
  });
</script>

<ScrollArea
  bind:viewport={scroller}
  axis="both"
  class="h-full min-h-0"
  viewportClass="h-full"
>
  <div class="min-w-max" style="--code-w: {showBinary ? '17rem' : '6rem'}">
    <div
      class="{COLS} sticky top-0 z-10 border-b border-border bg-surface-1 px-3 py-1.5 text-[9px] font-semibold uppercase tracking-[1px] text-text-faint"
    >
      <span class="text-center">BP</span>
      <span>Address</span>
      <span class="flex items-center gap-1.5">
        Code
        <button
          type="button"
          onclick={() => (showBinary = !showBinary)}
          aria-pressed={showBinary}
          title="Toggle binary view"
          class="cursor-pointer rounded mb-px px-1 py-px text-[8px] font-semibold leading-none tracking-[0.5px] transition-colors {showBinary
            ? 'bg-primary-soft text-primary'
            : 'border border-border-soft text-text-faint hover:border-primary hover:text-primary'}"
        >
          BIN
        </button>
      </span>
      <span>Basic</span>
      <span>Source</span>
    </div>

    {#each rows as row (`${row.kind}-${row.addr}`)}
      {#if row.kind === "pad"}
        <div
          class="{COLS} h-5 px-3 font-mono text-[11.5px] italic leading-5 text-text-ghost select-none"
          title="{row.bytes} bytes skipped between instructions (alignment padding / in-line data) - no instructions emitted here"
        >
          <span></span>
          <span class="text-secondary opacity-50"
            >{#if displayStore.hexMode}{toHex(
                row.addr,
              )}{:else}{row.addr}{/if}</span
          >
          <span class="col-span-3 flex items-center gap-2">
            <span class="h-px flex-1 border-t border-dashed border-border-soft"
            ></span>
            <span class="shrink-0 tracking-wide"
              >padding · {row.bytes} bytes</span
            >
            <span class="h-px flex-1 border-t border-dashed border-border-soft"
            ></span>
          </span>
        </div>
      {:else}
        {@const isPc = row.addr === pc}
        {@const isFlash = row.addr === flashAddr}
        {@const hasBp = cpuStore.breakpoints.has(row.addr)}
        <div
          data-addr={row.addr}
          class="{COLS} relative h-5 px-3 font-mono text-[11.5px] leading-5 transition-colors duration-500 {isFlash
            ? 'bg-primary-soft'
            : isPc
              ? "bg-primary-line before:absolute before:inset-y-0 before:left-0 before:w-0.5 before:bg-primary before:content-['']"
              : 'hover:bg-surface-2'}"
        >
          <button
            type="button"
            aria-label={hasBp ? "Remove breakpoint" : "Set breakpoint"}
            aria-pressed={hasBp}
            title={`line ${row.line}`}
            class="flex cursor-pointer h-full items-center justify-center"
            onclick={() => cpuStore.toggleBreakpointAddr(row.addr)}
          >
            <span
              class="h-2 w-2 rounded-full transition-colors {hasBp
                ? 'bg-red shadow-[0_0_6px_var(--color-red)]'
                : 'border border-border-soft hover:border-red'}"
            ></span>
          </button>

          <span class="text-secondary opacity-85"
            >{#if displayStore.hexMode}{toHex(
                row.addr,
              )}{:else}{row.addr}{/if}</span
          >
          <span class={isPc ? "text-primary" : "text-text-dim"}
            >{#if showBinary}{bin32(
                row.code,
              )}{:else if displayStore.hexMode}{toHex(
                row.code,
              )}{:else}{row.code}{/if}</span
          >
          <span class={isPc ? "text-text" : "text-text-dim"}>{row.basic}</span>
          <span class="truncate text-text-faint">
            {#if row.source !== null}<span class="mr-2 text-text-ghost"
                >{row.line}:</span
              >{row.source}{/if}
          </span>
        </div>
      {/if}
    {/each}

    <div class="h-3" aria-hidden="true"></div>
  </div>
</ScrollArea>
