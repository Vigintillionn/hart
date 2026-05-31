<script lang="ts">
  import { PaneResizer, type PaneAPI } from "paneforge";

  let {
    direction,
    pane,
  }: {
    direction: "horizontal" | "vertical";
    pane: PaneAPI | undefined;
  } = $props();

  const toggle = () => (pane?.isCollapsed() ? pane.expand() : pane?.collapse());
</script>

<PaneResizer
  class="relative z-10 bg-border transition-colors data-[resize-handle-state=hover]:bg-primary-soft data-[resize-handle-state=drag]:bg-primary {direction ===
  'vertical'
    ? 'h-px'
    : 'w-px'}"
>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="absolute {direction === 'vertical'
      ? 'inset-x-0 -top-1 -bottom-1 cursor-row-resize'
      : 'inset-y-0 -left-1 -right-1 cursor-col-resize'}"
    ondblclick={toggle}
  ></div>
</PaneResizer>
