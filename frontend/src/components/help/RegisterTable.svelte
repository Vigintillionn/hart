<script lang="ts">
  import type { RegisterInfo } from "$lib/store/helpCatalogue.svelte";
  import ReferenceTable from "./ReferenceTable.svelte";

  let { items }: { items: RegisterInfo[] } = $props();
</script>

<section class="mb-7 last:mb-0">
  <div class="mb-1 flex items-center gap">
    <h3 class="text-[12.5px] font-semibold text-text">
      General Purpose Registers
    </h3>
  </div>
  <p class="mb-4 text-[11px] leading-snug text-text-dim">
    Standard RISC-V integer calling conventions.
  </p>

  <ReferenceTable
    columns={["ABI Name", "Architecture Name", "Saver", "Description"]}
  >
    {#each items as r (r.abi)}
      <tr class="border-b border-border-soft align-top last:border-0">
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[12px] font-semibold text-primary"
        >
          {r.abi}
        </td>
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[12px] font-semibold text-text-dim"
        >
          {r.arch}
        </td>
        <td class="whitespace-nowrap pt-0.5 pr-4">
          {#if r.saver === "Caller"}
            <span
              class="rounded bg-primary-soft px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-primary"
            >
              Caller
            </span>
          {:else if r.saver === "Callee"}
            <span
              class="rounded bg-control px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-text-faint"
            >
              Callee
            </span>
          {:else}
            <span class="text-[11px] text-text-faint">-</span>
          {/if}
        </td>
        <td class="py-2 text-[11.5px] leading-snug text-text-dim">
          {r.desc}
        </td>
      </tr>
    {/each}
  </ReferenceTable>
</section>
