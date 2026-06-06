<!--
  `class` sizes/positions the box within its parent (e.g.
  `min-h-0 flex-1`, `h-full`); `viewportClass` sets the scroll extent + padding
  (`h-full` for a flex/filled box, or `max-h-...` for a content-sized popover)
-->
<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    class: klass = "",
    viewportClass = "",
    axis = "y",
    viewport = $bindable<HTMLElement | undefined>(),
    onscroll,
    children,
    ...rest
  }: {
    class?: string;
    viewportClass?: string;
    axis?: "y" | "x" | "both";
    viewport?: HTMLElement;
    onscroll?: (e: Event) => void;
    children: Snippet;
    [key: string]: unknown;
  } = $props();

  const THUMB_MIN = 28;
  const viewportId = `scrollarea-${globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2)}`;

  let clientH = $state(0);
  let clientW = $state(0);
  let scrollH = $state(0);
  let scrollW = $state(0);
  let scrollTop = $state(0);
  let scrollLeft = $state(0);

  let content = $state<HTMLElement>();
  let draggingY = $state(false);
  let draggingX = $state(false);

  function measure() {
    const el = viewport;
    if (!el) return;
    clientH = el.clientHeight;
    clientW = el.clientWidth;
    scrollH = el.scrollHeight;
    scrollW = el.scrollWidth;
    scrollTop = el.scrollTop;
    scrollLeft = el.scrollLeft;
  }

  function handleScroll(e: Event) {
    measure();
    onscroll?.(e);
  }

  $effect(() => {
    const el = viewport;
    if (!el) return;
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    if (content) ro.observe(content);
    return () => ro.disconnect();
  });

  const overflowClass = $derived(
    axis === "x"
      ? "overflow-x-auto overflow-y-hidden"
      : axis === "both"
        ? "overflow-auto"
        : "overflow-y-auto overflow-x-hidden",
  );

  const maxScrollTop = $derived(Math.max(0, scrollH - clientH));
  const maxScrollLeft = $derived(Math.max(0, scrollW - clientW));
  const showY = $derived((axis === "y" || axis === "both") && maxScrollTop > 1);
  const showX = $derived(
    (axis === "x" || axis === "both") && maxScrollLeft > 1,
  );

  const thumbH = $derived(
    scrollH > 0 ? Math.max(THUMB_MIN, (clientH / scrollH) * clientH) : 0,
  );
  const thumbTop = $derived(
    maxScrollTop > 0 ? (scrollTop / maxScrollTop) * (clientH - thumbH) : 0,
  );
  const thumbW = $derived(
    scrollW > 0 ? Math.max(THUMB_MIN, (clientW / scrollW) * clientW) : 0,
  );
  const thumbLeft = $derived(
    maxScrollLeft > 0 ? (scrollLeft / maxScrollLeft) * (clientW - thumbW) : 0,
  );

  const scrollPctY = $derived(
    maxScrollTop > 0 ? Math.round((scrollTop / maxScrollTop) * 100) : 0,
  );
  const scrollPctX = $derived(
    maxScrollLeft > 0 ? Math.round((scrollLeft / maxScrollLeft) * 100) : 0,
  );

  let dragStart = 0;
  let dragStartScroll = 0;

  function beginDragY(e: PointerEvent) {
    if (e.button !== 0 || !viewport) return;
    e.preventDefault();
    e.stopPropagation();
    draggingY = true;
    dragStart = e.clientY;
    dragStartScroll = viewport.scrollTop;
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
  }
  function moveDragY(e: PointerEvent) {
    if (!draggingY || !viewport) return;
    const travel = clientH - thumbH;
    if (travel <= 0) return;
    viewport.scrollTop =
      dragStartScroll + ((e.clientY - dragStart) / travel) * maxScrollTop;
  }
  function trackDownY(e: PointerEvent) {
    if (e.button !== 0 || !viewport) return;
    const rect = (e.currentTarget as Element).getBoundingClientRect();
    const frac =
      (e.clientY - rect.top - thumbH / 2) / Math.max(1, clientH - thumbH);
    viewport.scrollTop = Math.min(1, Math.max(0, frac)) * maxScrollTop;
    beginDragY(e);
  }

  function beginDragX(e: PointerEvent) {
    if (e.button !== 0 || !viewport) return;
    e.preventDefault();
    e.stopPropagation();
    draggingX = true;
    dragStart = e.clientX;
    dragStartScroll = viewport.scrollLeft;
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
  }
  function moveDragX(e: PointerEvent) {
    if (!draggingX || !viewport) return;
    const travel = clientW - thumbW;
    if (travel <= 0) return;
    viewport.scrollLeft =
      dragStartScroll + ((e.clientX - dragStart) / travel) * maxScrollLeft;
  }
  function trackDownX(e: PointerEvent) {
    if (e.button !== 0 || !viewport) return;
    const rect = (e.currentTarget as Element).getBoundingClientRect();
    const frac =
      (e.clientX - rect.left - thumbW / 2) / Math.max(1, clientW - thumbW);
    viewport.scrollLeft = Math.min(1, Math.max(0, frac)) * maxScrollLeft;
    beginDragX(e);
  }

  function endDrag(e: PointerEvent) {
    draggingY = false;
    draggingX = false;
    const el = e.currentTarget as Element;
    if (el.hasPointerCapture(e.pointerId))
      el.releasePointerCapture(e.pointerId);
  }
</script>

<div class="relative {klass}" {...rest}>
  <div
    bind:this={viewport}
    id={viewportId}
    class="hide-native-scroll {overflowClass} {viewportClass}"
    onscroll={handleScroll}
  >
    <div bind:this={content} class={axis === "y" ? "" : "w-max min-w-full"}>
      {@render children()}
    </div>
  </div>

  {#if showY}
    <div
      role="scrollbar"
      tabindex={-1}
      aria-orientation="vertical"
      aria-label="Vertical scrollbar"
      aria-controls={viewportId}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={scrollPctY}
      class="absolute right-0 top-0 z-20 w-2.5 touch-none {showX
        ? 'bottom-2.5'
        : 'bottom-0'}"
      onpointerdown={trackDownY}
      onpointermove={moveDragY}
      onpointerup={endDrag}
      onpointercancel={endDrag}
    >
      <div
        aria-hidden="true"
        class="absolute inset-x-0.5 rounded-full transition-colors {draggingY
          ? 'bg-thumb-active'
          : 'bg-thumb hover:bg-thumb-hover'}"
        style="top: {thumbTop}px; height: {thumbH}px;"
      ></div>
    </div>
  {/if}

  {#if showX}
    <div
      role="scrollbar"
      tabindex={-1}
      aria-orientation="horizontal"
      aria-label="Horizontal scrollbar"
      aria-controls={viewportId}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={scrollPctX}
      class="absolute bottom-0 left-0 z-20 h-2.5 touch-none {showY
        ? 'right-2.5'
        : 'right-0'}"
      onpointerdown={trackDownX}
      onpointermove={moveDragX}
      onpointerup={endDrag}
      onpointercancel={endDrag}
    >
      <div
        aria-hidden="true"
        class="absolute inset-y-0.5 rounded-full transition-colors {draggingX
          ? 'bg-thumb-active'
          : 'bg-thumb hover:bg-thumb-hover'}"
        style="left: {thumbLeft}px; width: {thumbW}px;"
      ></div>
    </div>
  {/if}
</div>
