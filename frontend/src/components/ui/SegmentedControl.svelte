<script lang="ts" generics="T">
  let {
    options,
    value = $bindable(),
    size = "md",
    accent = "primary",
  }: {
    options: { value: T; label: string }[];
    value: T;
    size?: "sm" | "md";
    accent?: "primary" | "text";
  } = $props();

  const item = $derived(
    size === "sm"
      ? "rounded-sm px-2 py-0.5 text-[10px] uppercase tracking-[1px]"
      : "rounded-[5px] px-2.5 py-1 font-mono text-[11px] tracking-[0.3px]",
  );
  const activeText = $derived(
    accent === "primary" ? "text-primary" : "text-text",
  );
  const indicatorRounded = $derived(
    size === "sm" ? "rounded-sm" : "rounded-[5px]",
  );

  let buttons = $state<HTMLButtonElement[]>([]);
  let indicator = $state({
    left: 0,
    top: 0,
    width: 0,
    height: 0,
    ready: false,
  });

  const activeIndex = $derived(options.findIndex((o) => o.value === value));

  function measure() {
    const el = buttons[activeIndex];
    if (!el) return;
    indicator = {
      left: el.offsetLeft,
      top: el.offsetTop,
      width: el.offsetWidth,
      height: el.offsetHeight,
      ready: true,
    };
  }

  $effect(() => {
    // depend on the active item and the option set so the indicator
    // re-measures whenever either changes
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    [activeIndex, options];
    measure();
  });

  let animate = $state(false);
  $effect(() => {
    if (indicator.ready && !animate) {
      const id = requestAnimationFrame(() => (animate = true));
      return () => cancelAnimationFrame(id);
    }
  });
</script>

<div
  class="relative inline-flex gap-0.5 rounded-md border border-border bg-surface-0 p-0.5"
  {@attach (node) => {
    const ro = new ResizeObserver(() => measure());
    ro.observe(node);
    return () => ro.disconnect();
  }}
>
  <div
    class={[
      "pointer-events-none absolute bg-control",
      animate && "transition-all duration-200 ease-out",
      indicatorRounded,
      indicator.ready ? "opacity-100" : "opacity-0",
    ]}
    style="left: {indicator.left}px; top: {indicator.top}px; width: {indicator.width}px; height: {indicator.height}px"
  ></div>

  {#each options as opt, i (String(opt.value))}
    <button
      bind:this={buttons[i]}
      class="relative z-10 font-semibold cursor-pointer transition-colors {item} {value ===
      opt.value
        ? activeText
        : 'text-text-faint hover:text-text-dim'}"
      aria-pressed={value === opt.value}
      onclick={() => (value = opt.value)}>{opt.label}</button
    >
  {/each}
</div>
