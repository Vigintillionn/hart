<script lang="ts">
  import { helpStore } from "$lib/store/helpStore.svelte";
  import { helpCatalogue } from "$lib/store/helpCatalogue.svelte";
  import ExtensionSection from "./ExtensionSection.svelte";
  import PseudoTable from "./PseudoTable.svelte";
  import SyscallTable from "./SyscallTable.svelte";
  import AsciiTable from "./AsciiTable.svelte";
  import RegisterTable from "./RegisterTable.svelte";
  import DirectiveTable from "./DirectiveTable.svelte";
  import CsrTable from "./CsrTable.svelte";
  import BaseConverter from "./BaseConverter.svelte";
  import ScrollArea from "../ui/ScrollArea.svelte";
</script>

<ScrollArea class="min-h-0 flex-1" viewportClass="h-full px-5 py-4">
  {#if helpStore.group === "converter"}
    <BaseConverter />
  {:else}
    {#each helpCatalogue.extSections as section (section.code)}
      <ExtensionSection {section} />
    {/each}

    {#if helpCatalogue.visiblePseudos.length}
      <PseudoTable pseudos={helpCatalogue.visiblePseudos} />
    {/if}

    {#if helpCatalogue.visibleDirectives.length}
      <DirectiveTable directives={helpCatalogue.visibleDirectives} />
    {/if}

    {#if helpCatalogue.visibleSyscalls.length}
      <SyscallTable syscalls={helpCatalogue.visibleSyscalls} />
    {/if}

    {#if helpCatalogue.visibleCsrs.length}
      <CsrTable csrs={helpCatalogue.visibleCsrs} />
    {/if}

    {#if helpCatalogue.visibleRegisters.length}
      <RegisterTable items={helpCatalogue.visibleRegisters} />
    {/if}
    {#if helpCatalogue.visibleAscii.length}
      <AsciiTable items={helpCatalogue.visibleAscii} />
    {/if}

    {#if helpCatalogue.isEmpty}
      <p class="py-6 text-center text-[12px] text-text-faint">
        Nothing matches “{helpStore.query}”.
      </p>
    {/if}
  {/if}
</ScrollArea>
