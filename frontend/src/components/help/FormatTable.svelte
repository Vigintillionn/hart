<script lang="ts">
  import type { FormatInfo } from "../../bindings/FormatInfo";
  import type { InstructionInfo } from "../../bindings/InstructionInfo";
  import ReferenceTable from "./ReferenceTable.svelte";
  import BitFields from "./BitFields.svelte";

  let {
    fmt,
    items,
    dim = false,
  }: { fmt: FormatInfo; items: InstructionInfo[]; dim?: boolean } = $props();
</script>

<div class="mb-5 last:mb-0">
  <div
    class="mb-2.5 rounded-lg border border-border-soft bg-surface-1/60 px-3 py-2.5"
  >
    <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
      <span class="text-[11.5px] font-medium text-text">
        {fmt.name}
        <span class="text-text-faint">· {fmt.kind}</span>
      </span>
      <code class="font-mono text-[11px] text-text-dim">
        &lt;instr&gt;{fmt.syntax ? " " + fmt.syntax : ""}
      </code>
    </div>
    <p class="mt-1 text-[11px] leading-snug text-text-dim">{fmt.blurb}</p>
    {#if fmt.operands.length}
      <div class="mt-1.5 flex flex-wrap gap-x-3 gap-y-1">
        {#each fmt.operands as op (op.token)}
          <span class="text-[10.5px] text-text-faint">
            <code class="font-mono text-text-dim">{op.token}</code>
            {op.desc}
          </span>
        {/each}
      </div>
    {/if}

    <BitFields fields={fmt.fields} {dim} />
  </div>

  <ReferenceTable columns={["Syntax", "Operation", "Description"]} {dim}>
    {#each items as i (i.mnemonic)}
      <tr class="border-b border-border-soft align-top last:border-0">
        <td class="whitespace-nowrap py-2 pr-4 font-mono text-[12px]">
          <span class="inline-flex gap-2">
            <span class="font-semibold text-primary">{i.mnemonic}</span>
            {#if fmt.syntax}
              <span class="text-text-dim">{fmt.syntax}</span>
            {/if}
          </span>
        </td>
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[11.5px] text-text-dim"
          >{i.operation}</td
        >
        <td class="py-2 text-[11.5px] leading-snug text-text-dim"
          >{i.description}</td
        >
      </tr>
    {/each}
  </ReferenceTable>
</div>
