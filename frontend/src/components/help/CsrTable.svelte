<script lang="ts">
  import type { CsrInfo } from "../../bindings/CsrInfo";
  import ReferenceTable from "./ReferenceTable.svelte";

  let { csrs }: { csrs: CsrInfo[] } = $props();
</script>

<section class="mb-7 last:mb-0">
  <div class="mb-1 flex items-center gap-2">
    <h3 class="text-[12.5px] font-semibold text-text">
      Control &amp; status registers
    </h3>
  </div>
  <p class="mb-3 text-[11px] leading-snug text-text-dim">
    Machine-level CSRs the emulator implements. Access them by name or address
    with the <code class="font-mono text-text-dim">csrr*</code> instructions.
  </p>
  <ReferenceTable columns={["Name", "Address", "Description"]}>
    {#each csrs as c (c.address)}
      <tr class="border-b border-border-soft align-top last:border-0">
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[12px] font-semibold text-primary"
          >{c.name}</td
        >
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[11.5px] text-text-dim"
          >{c.address}</td
        >
        <td class="py-2 text-[11.5px] leading-snug text-text-dim"
          >{c.description}</td
        >
      </tr>
    {/each}
  </ReferenceTable>
</section>
