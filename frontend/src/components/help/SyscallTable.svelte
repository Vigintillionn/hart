<script lang="ts">
  import type { RegisterUse } from "../../bindings/RegisterUse";
  import type { SyscallInfo } from "../../bindings/SyscallInfo";
  import ReferenceTable from "./ReferenceTable.svelte";

  let { syscalls }: { syscalls: SyscallInfo[] } = $props();
</script>

<section class="mb-7 last:mb-0">
  <div class="mb-1 flex items-center gap-2">
    <h3 class="text-[12.5px] font-semibold text-text">System calls</h3>
  </div>
  <p class="mb-3 text-[11px] leading-snug text-text-dim">
    Services the runtime provides through <code class="font-mono text-text-dim"
      >ecall</code
    >. Put the call number in <code class="font-mono text-text-dim">a7</code>,
    arguments in <code class="font-mono text-text-dim">a0…a2</code>, then
    execute
    <code class="font-mono text-text-dim">ecall</code>.
  </p>
  <ReferenceTable columns={["Call", "a7", "Registers", "Description"]}>
    {#each syscalls as s (s.code)}
      <tr class="border-b border-border-soft align-top last:border-0">
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[12px] font-semibold text-primary"
          >{s.name}</td
        >
        <td
          class="whitespace-nowrap py-2 pr-4 font-mono text-[11.5px] text-text-dim"
          >{s.code}</td
        >
        <td class="whitespace-nowrap py-2 pr-4">
          {#if s.registers.length}
            <div class="flex flex-col gap-1">
              {#each s.registers as r (r.dir + r.reg + r.desc)}
                {@render registerLine(r)}
              {/each}
            </div>
          {:else}
            <span class="text-[11px] text-text-faint">-</span>
          {/if}
        </td>
        <td class="py-2 text-[11.5px] leading-snug text-text-dim"
          >{s.description}</td
        >
      </tr>
    {/each}
  </ReferenceTable>
</section>

{#snippet registerLine(r: RegisterUse)}
  <span class="flex items-center gap-1.5 font-mono text-[11px] text-text-faint">
    <span
      class={[
        "rounded px-1 py-px text-[9px] font-semibold uppercase tracking-wide",
        r.dir === "out"
          ? "bg-primary-soft text-primary"
          : "bg-control text-text-faint",
      ]}
    >
      {r.dir === "out" ? "ret" : "arg"}
    </span>
    <span>
      <span class="text-text-dim">{r.reg}</span>
      = {r.desc}
    </span>
  </span>
{/snippet}
