<script lang="ts">
  import type { Snippet } from "svelte";

  let {
    columns,
    dim = false,
    children,
  }: { columns: string[]; dim?: boolean; children: Snippet } = $props();
</script>

<table class={["w-full border-collapse text-left", dim && "opacity-45"]}>
  <thead>
    <tr
      class="border-b border-border text-[10px] uppercase tracking-[1px] text-text-faint"
    >
      {#each columns as col, i (col)}
        <th
          class={[
            "py-1.5 font-semibold",
            i < columns.length - 1 && "w-px whitespace-nowrap pr-4",
          ]}>{col}</th
        >
      {/each}
    </tr>
  </thead>
  <tbody>
    {@render children()}
  </tbody>
</table>
