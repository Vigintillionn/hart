<script lang="ts">
  interface Props {
    mem: Array<[bigint | number, number]>;
  }

  let { mem }: Props = $props();

  const DEFAULT_MEMORY_ADDRESS = 0x00000000;
  const BYTES_PER_LINE = 16;
  const LINES = 16;

  let baseAddress = $state(DEFAULT_MEMORY_ADDRESS);
  let searchInput = $state("");

  let memMap = $derived.by(() => {
    const map = new Map<number, number>();
    for (const [addr, val] of mem) {
      map.set(Number(addr), val);
    }
    return map;
  });

  let displayLines = $derived.by(() => {
    const lines = [];
    for (let i = 0; i < LINES; i++) {
      const lineAddr = baseAddress + i * BYTES_PER_LINE;
      const bytes = [];
      let ascii = "";

      for (let j = 0; j < BYTES_PER_LINE; j++) {
        const addr = lineAddr + j;
        const val = memMap.get(addr) ?? 0;
        bytes.push(val.toString(16).padStart(2, "0").toUpperCase());

        // Printable ASCII range
        if (val >= 32 && val <= 126) {
          ascii += String.fromCharCode(val);
        } else {
          ascii += ".";
        }
      }

      lines.push({
        addrStr: "0x" + lineAddr.toString(16).padStart(8, "0").toUpperCase(),
        bytesStr: bytes.join(" "),
        ascii,
      });
    }
    return lines;
  });

  const handleSearch = (e: Event) => {
    e.preventDefault();
    let addr = parseInt(searchInput, 16);
    if (!isNaN(addr)) {
      // align to BYTES_PER_LINE
      baseAddress = Math.floor(addr / BYTES_PER_LINE) * BYTES_PER_LINE;
    }
  };

  const handlePrev = () => {
    baseAddress = Math.max(0, baseAddress - BYTES_PER_LINE * LINES);
  };

  const handleNext = () => {
    baseAddress += BYTES_PER_LINE * LINES;
  };

  const handleWheel = (e: WheelEvent) => {
    if (e.deltaY > 0) {
      baseAddress += BYTES_PER_LINE * 2;
    } else if (e.deltaY < 0) {
      baseAddress = Math.max(0, baseAddress - BYTES_PER_LINE * 2);
    }
    baseAddress = Math.min(maxAddress, baseAddress);
  };

  const maxAddress = 0xffffffff - BYTES_PER_LINE * LINES + 1;
  let scrollPercent = $derived((baseAddress / maxAddress) * 100);

  let trackNode: HTMLElement;
  let isDragging = false;

  const updateScrollFromEvent = (e: MouseEvent) => {
    if (!trackNode) return;
    const rect = trackNode.getBoundingClientRect();
    let percent = (e.clientY - rect.top) / rect.height;
    percent = Math.max(0, Math.min(1, percent));
    baseAddress =
      Math.floor((percent * maxAddress) / BYTES_PER_LINE) * BYTES_PER_LINE;
  };

  const handleDragStart = (e: MouseEvent) => {
    isDragging = true;
    updateScrollFromEvent(e);
    window.addEventListener("mousemove", handleDragMove);
    window.addEventListener("mouseup", handleDragEnd);
  };

  const handleDragMove = (e: MouseEvent) => {
    if (isDragging) updateScrollFromEvent(e);
  };

  const handleDragEnd = () => {
    isDragging = false;
    window.removeEventListener("mousemove", handleDragMove);
    window.removeEventListener("mouseup", handleDragEnd);
  };
</script>

<div
  class="flex flex-col h-full bg-zinc-950 border-t border-zinc-800 font-mono text-sm"
>
  <div
    class="flex items-center justify-between px-3 py-2 bg-zinc-900 border-b border-zinc-800"
  >
    <div
      class="text-xs uppercase tracking-wider text-zinc-500 font-sans font-semibold"
    >
      Memory
    </div>
    <div class="flex gap-2 items-center">
      <button
        class="px-2 py-1 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded border-none cursor-pointer transition-colors"
        onclick={handlePrev}
      >
        ▲ Prev
      </button>
      <button
        class="px-2 py-1 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 rounded border-none cursor-pointer transition-colors"
        onclick={handleNext}
      >
        ▼ Next
      </button>
      <form onsubmit={handleSearch} class="flex ml-2">
        <input
          type="text"
          bind:value={searchInput}
          placeholder="0x00000000"
          class="bg-zinc-950 border border-zinc-700 text-zinc-300 px-2 py-1 rounded-l outline-none focus:border-sky-500 w-28 text-xs font-mono"
        />
        <button
          type="submit"
          class="bg-sky-600 hover:bg-sky-500 text-white px-2 py-1 rounded-r border-none cursor-pointer transition-colors text-xs"
        >
          Go
        </button>
      </form>
    </div>
  </div>

  <div class="flex flex-1 overflow-hidden">
    <div class="p-4 overflow-y-hidden overflow-x-auto flex-1" onwheel={handleWheel}>
      {#each displayLines as line}
        <div class="flex items-center hover:bg-zinc-900/50 px-2 py-0.5 rounded w-max gap-6">
          <span class="text-zinc-500 shrink-0 select-none">{line.addrStr}</span>
          <span class="text-sky-300 shrink-0 tracking-widest whitespace-nowrap">{line.bytesStr}</span>
          <span class="text-zinc-400 opacity-80 shrink-0 whitespace-pre">{line.ascii}</span>
        </div>
      {/each}
    </div>

    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      bind:this={trackNode}
      class="w-3 bg-zinc-950 border-l border-zinc-800 relative cursor-pointer"
      onmousedown={handleDragStart}
    >
      <div
        class="absolute w-full bg-zinc-700 hover:bg-zinc-500 rounded-full transition-colors"
        style="top: calc({scrollPercent}% - 10px); height: 20px; left: 0; right: 0;"
      ></div>
    </div>
  </div>
</div>
