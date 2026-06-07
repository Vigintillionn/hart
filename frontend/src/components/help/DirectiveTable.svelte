<script lang="ts">
  import type { DirectiveInfo } from "../../bindings/DirectiveInfo";
  import ReferenceTable from "./ReferenceTable.svelte";

  let { directives }: { directives: DirectiveInfo[] } = $props();
</script>

<section class="mb-7 last:mb-0">
  <div class="mb-1 flex items-center gap-2">
    <h3 class="text-[12.5px] font-semibold text-text">Assembler directives</h3>
  </div>
  <p class="mb-3 text-[11px] leading-snug text-text-dim">
    Commands to the assembler that lay out data and switch sections rather than
    emitting instructions.
  </p>
  <ReferenceTable columns={["Directive", "Operands", "Description"]}>
    {#each directives as d (d.name)}
      <tr class="border-b border-border-soft align-top last:border-0">
        <td class="whitespace-nowrap py-2 pr-4 font-mono text-[12px]">
          <span class="font-semibold text-primary">{d.name}</span>
        </td>
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[11px] text-text-faint"
          >{d.args || "-"}</td
        >
        <td class="py-2 text-[11.5px] leading-snug text-text-dim"
          >{d.description}</td
        >
      </tr>
    {/each}
  </ReferenceTable>
</section>
