<script lang="ts">
  import { untrack } from "svelte";
  import { layoutStore } from "$lib/store/layoutStore.svelte";
  import { hex32, hex2, TEXT_BASE, DATA_BASE, STACK_TOP } from "$lib/util";
  import Icon from "../Icon.svelte";

  let { mem }: { mem: Array<[bigint | number, number]> } = $props();

  const ROW_BYTES = 16;
  const ROW_PX = 20;

  let base = $state(DATA_BASE);
  let follow = $state(true);
  let query = $state("");

  let viewportH = $state(0);
  const visibleRows = $derived(Math.max(1, Math.ceil(viewportH / ROW_PX) + 1));

  let memMap = $derived.by(() => {
    const map = new Map<number, number>();
    for (const [addr, val] of mem) map.set(Number(addr), val);
    return map;
  });

  const usedBytes = $derived(memMap.size);

  function clampBase(b: number): number {
    const span = visibleRows * ROW_BYTES;
    const maxBase = (STACK_TOP + 1 - span) & ~0xf;
    if (b < 0) return 0;
    if (b > maxBase) return maxBase;
    return b & ~0xf;
  }

  let wheelAccum = 0;
  function onWheel(e: WheelEvent) {
    if (e.shiftKey || Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
    e.preventDefault();
    follow = false;
    wheelAccum += e.deltaMode === 1 ? e.deltaY * ROW_PX : e.deltaY;
    const rowsToMove = Math.trunc(wheelAccum / ROW_PX);
    if (rowsToMove !== 0) {
      wheelAccum -= rowsToMove * ROW_PX;
      base = clampBase(base + rowsToMove * ROW_BYTES);
    }
  }

  function onKeydown(e: KeyboardEvent) {
    let rows = 0;
    if (e.key === "ArrowDown") rows = 1;
    else if (e.key === "ArrowUp") rows = -1;
    else if (e.key === "PageDown") rows = Math.max(1, visibleRows - 2);
    else if (e.key === "PageUp") rows = -Math.max(1, visibleRows - 2);
    else return;
    e.preventDefault();
    follow = false;
    base = clampBase(base + rows * ROW_BYTES);
  }

  let prevMem: Map<number, number> = new Map();
  let changed = $state<Set<number>>(new Set());
  let flashTimer: number;

  $effect(() => {
    const cur = memMap;
    untrack(() => {
      if (prevMem.size || cur.size) {
        const diff = new Set<number>();
        const keys = new Set([...prevMem.keys(), ...cur.keys()]);
        for (const a of keys)
          if ((prevMem.get(a) ?? 0) !== (cur.get(a) ?? 0)) diff.add(a >>> 0);
        if (diff.size) {
          changed = diff;
          if (follow) base = clampBase(Math.min(...diff));
          clearTimeout(flashTimer);
          flashTimer = window.setTimeout(() => (changed = new Set()), 680);
        }
      }
      prevMem = new Map(cur);
    });
  });

  const rows = $derived.by(() => {
    const out: { addr: number; bytes: number[] }[] = [];
    for (let r = 0; r < visibleRows; r++) {
      const addr = (base + r * ROW_BYTES) >>> 0;
      const bytes: number[] = [];
      for (let c = 0; c < ROW_BYTES; c++) bytes.push(memMap.get(addr + c) ?? 0);
      out.push({ addr, bytes });
    }
    return out;
  });

  const submit = (e: Event) => {
    e.preventDefault();
    const t = query.trim().toLowerCase();
    if (!t) return;
    const addr = t.startsWith("0x") ? parseInt(t, 16) : parseInt(t, 10);
    if (!isNaN(addr)) {
      follow = false;
      base = clampBase(addr >>> 0);
    }
  };

  const THUMB_H = 28;
  let trackNode: HTMLElement | undefined = $state();
  let trackH = $state(0);
  let dragging = $state(false);

  const maxBase = $derived((STACK_TOP + 1 - visibleRows * ROW_BYTES) & ~0xf);
  const scrollFrac = $derived(
    maxBase > 0 ? Math.min(1, Math.max(0, base / maxBase)) : 0,
  );
  const usableTrack = $derived(Math.max(0, trackH - THUMB_H));
  const thumbTop = $derived(scrollFrac * usableTrack);

  let dragStartY = 0;
  let dragStartBase = 0;

  const onDragMove = (e: MouseEvent) => {
    if (!dragging || usableTrack <= 0) return;
    const dFrac = (e.clientY - dragStartY) / usableTrack;
    base = clampBase(dragStartBase + dFrac * maxBase);
  };

  const onDragEnd = () => {
    dragging = false;
    window.removeEventListener("mousemove", onDragMove);
    window.removeEventListener("mouseup", onDragEnd);
  };

  const beginDrag = (startBase: number, clientY: number) => {
    follow = false;
    dragging = true;
    dragStartBase = startBase;
    dragStartY = clientY;
    window.addEventListener("mousemove", onDragMove);
    window.addEventListener("mouseup", onDragEnd);
  };

  const onThumbDown = (e: MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    beginDrag(base, e.clientY);
  };

  const onTrackDown = (e: MouseEvent) => {
    if (!trackNode || usableTrack <= 0) return;
    const rect = trackNode.getBoundingClientRect();
    const frac = Math.min(
      1,
      Math.max(0, (e.clientY - rect.top - THUMB_H / 2) / usableTrack),
    );
    follow = false;
    base = clampBase(frac * maxBase);
    beginDrag(base, e.clientY);
  };
</script>

<div class="flex h-full min-h-0 flex-col">
  <div
    class="flex h-8.25 flex-none items-center gap-2 border-b border-border bg-surface-1 px-4"
  >
    <span class="h-2.75 w-0.75 rounded-sm bg-primary"></span>
    <span
      class="text-[10.5px] font-semibold uppercase tracking-[1.5px] text-text-dim"
      >Memory</span
    >
    <span
      class="ml-auto font-mono text-[10px] text-text-faint"
      title="Total bytes allocated by the program"
      >{usedBytes.toLocaleString()} bytes</span
    >
  </div>

  <div
    class="flex flex-none items-center gap-2 border-b border-border bg-surface-1 px-3 py-2"
  >
    <form
      onsubmit={submit}
      class="flex flex-1 items-center gap-2 rounded-md border border-border bg-surface-0 px-2.5 py-1.5 transition focus-within:border-primary-soft focus-within:shadow-[0_0_0_3px_var(--color-primary-line)]"
    >
      <Icon name="search" class="h-3 w-3 flex-none text-text-faint" />
      <input
        bind:value={query}
        spellcheck="false"
        placeholder="jump to address — 0x10000000"
        class="min-w-0 flex-1 bg-transparent font-mono text-[11.5px] tracking-[0.3px] text-text outline-none placeholder:text-text-ghost"
      />
    </form>
    <div class="flex gap-1">
      {#snippet chip(label: string, active: boolean, onClick: () => void)}
        <button
          class="rounded-[5px] border px-2 py-1.25 font-mono text-[10px] font-semibold transition-colors {active
            ? 'border-primary-soft bg-primary-line text-primary'
            : 'border-border bg-surface-0 text-text-faint hover:border-primary-soft hover:text-primary'}"
          onclick={onClick}>{label}</button
        >
      {/snippet}
      {@render chip(".text", base === (TEXT_BASE & ~0xf), () => {
        follow = false;
        base = clampBase(TEXT_BASE);
      })}
      {@render chip(".data", base === (DATA_BASE & ~0xf), () => {
        follow = false;
        base = clampBase(DATA_BASE);
      })}
      {@render chip("stack", false, () => {
        follow = false;
        base = clampBase(STACK_TOP - 0xf0);
      })}
      {@render chip("⌖ writes", follow, () => (follow = !follow))}
    </div>
  </div>

  <div class="relative flex min-h-0 flex-1 bg-surface-0">
    <div
      class="scroll-thin min-h-0 flex-1 overflow-x-auto overflow-y-hidden outline-none"
      tabindex="0"
      role="grid"
      aria-label="Memory view — scroll or arrow keys to navigate"
      bind:clientHeight={viewportH}
      onwheel={onWheel}
      onkeydown={onKeydown}
    >
      <div class="min-w-max">
        {#each rows as { addr, bytes } (addr)}
          <div
            class="flex h-5 items-center whitespace-pre px-3 font-mono text-[11.5px] leading-5 hover:bg-surface-1"
          >
            <span class="mr-3.5 text-secondary opacity-85">{hex32(addr)}</span>
            <span class="text-text-dim">
              {#each bytes as b, c}
                <span
                  class={changed.has((addr + c) >>> 0)
                    ? "text-primary"
                    : b === 0
                      ? "text-text-ghost"
                      : ""}
                  >{layoutStore.hexMode
                    ? hex2(b)
                    : b.toString().padStart(3, "0")}{" "}</span
                >{#if c === 7}<span class="inline-block w-2"></span>{/if}
              {/each}
            </span>
            <span class="ml-3 text-text-faint">
              {#each bytes as b, c}
                {@const pr = b >= 32 && b < 127}
                <span
                  class={changed.has((addr + c) >>> 0)
                    ? "text-primary"
                    : pr
                      ? "text-text-dim"
                      : ""}>{pr ? String.fromCharCode(b) : "·"}</span
                >
              {/each}
            </span>
          </div>
        {/each}
      </div>
    </div>

    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      bind:this={trackNode}
      bind:clientHeight={trackH}
      class="relative w-2.5 flex-none cursor-pointer border-l border-border"
      onmousedown={onTrackDown}
    >
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="absolute inset-x-0.5 rounded-full transition-colors {dragging
          ? 'bg-[rgba(255,255,255,0.28)]'
          : 'bg-[rgba(255,255,255,0.13)] hover:bg-[rgba(255,255,255,0.22)]'}"
        style="top: {thumbTop}px; height: {THUMB_H}px;"
        onmousedown={onThumbDown}
      ></div>
    </div>
  </div>
</div>
