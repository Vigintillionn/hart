<script lang="ts">
  import type { FieldDoc } from "../../bindings/FieldDoc";

  let { fields, dim = false }: { fields: FieldDoc[]; dim?: boolean } = $props();

  const ROLE: Record<string, string> = {
    opcode: "bg-secondary-soft text-secondary",
    reg: "bg-primary-soft text-primary",
    imm: "bg-amber/15 text-amber",
    funct: "bg-surface-3 text-text-dim",
    zero: "bg-surface-2 text-text-faint",
  };

  const cls = (role: string) => ROLE[role] ?? ROLE.funct;
  const width = (f: FieldDoc) => f.hi - f.lo + 1;
  const range = (f: FieldDoc) =>
    f.hi === f.lo ? `${f.hi}` : `${f.hi}:${f.lo}`;
</script>

{#if fields.length}
  <div
    class="mt-2.5 border-t border-border-soft pt-2.5 {dim ? 'opacity-50' : ''}"
  >
    <div
      class="mb-1 text-[10px] font-medium uppercase tracking-wide text-text-faint"
    >
      Encoding
    </div>
    <div class="overflow-x-auto">
      <div
        class="flex items-stretch overflow-hidden rounded-md border border-border-soft"
      >
        {#each fields as f (f.name + "@" + f.hi)}
          <div
            class="flex flex-col items-center justify-center gap-0.5 border-r border-border-soft px-1 py-1.5 text-center last:border-r-0 {cls(
              f.role,
            )}"
            style="flex: {width(f)} 0 0; min-width: 2.1rem"
            title="{f.name} · instruction bits {range(f)} ({width(f)}-bit)"
          >
            <span
              class="max-w-full truncate font-mono text-[10.5px] leading-none"
            >
              {f.name}
            </span>
            <span class="font-mono text-[9px] leading-none text-text-faint">
              {range(f)}
            </span>
          </div>
        {/each}
      </div>
    </div>
  </div>
{/if}
