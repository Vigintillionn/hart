<script lang="ts">
  import type { PseudoInfo } from "../../bindings/PseudoInfo";
  import ReferenceTable from "./ReferenceTable.svelte";

  let { pseudos }: { pseudos: PseudoInfo[] } = $props();
</script>

<section class="mb-7 last:mb-0">
  <div class="mb-1 flex items-center gap-2">
    <h3 class="text-[12.5px] font-semibold text-text">Pseudo-instructions</h3>
  </div>
  <p class="mb-3 text-[11px] leading-snug text-text-dim">
    Convenience mnemonics the assembler rewrites into one or more real
    instructions.
  </p>
  <ReferenceTable columns={["Syntax", "Expands to", "Description"]}>
    {#each pseudos as p (p.mnemonic + p.syntax)}
      <tr class="border-b border-border-soft align-top last:border-0">
        <td class="whitespace-nowrap py-2 pr-4 font-mono text-[12px]">
          <span class="inline-flex gap-2">
            <span class="font-semibold text-primary">{p.mnemonic}</span>
            {#if p.syntax}
              <span class="text-text-dim">{p.syntax}</span>
            {/if}
          </span>
        </td>
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[11px] text-text-faint"
          >{p.expands}</td
        >
        <td class="py-2 text-[11.5px] leading-snug text-text-dim"
          >{p.description}</td
        >
      </tr>
    {/each}
  </ReferenceTable>
</section>
