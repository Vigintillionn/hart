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
  class="group relative z-10 flex shrink-0 items-center justify-center bg-transparent {direction ===
  'vertical'
    ? 'h-1.5 w-full cursor-row-resize'
    : 'h-full w-1.5 cursor-col-resize'}"
>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="absolute inset-0" ondblclick={toggle}></div>
  <div
    class="bg-border transition-colors group-data-[resize-handle-state=hover]:bg-primary-soft group-data-[resize-handle-state=drag]:bg-primary {direction ===
    'vertical'
      ? 'h-px w-full'
      : 'h-full w-px'}"
  ></div>
</PaneResizer>
