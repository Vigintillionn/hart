<script lang="ts">
  import { terminalStore } from "$lib/store/terminalStore.svelte";
  import { logStore } from "$lib/store/logStore.svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import Terminal from "./Terminal.svelte";
  import Icon from "../Icon.svelte";
  import IconButton from "../ui/IconButton.svelte";

  const tagColor: Record<string, string> = {
    info: "text-primary",
    exec: "text-secondary",
    warn: "text-amber",
    error: "text-red",
  };

  const stdout = $derived(terminalStore.program.logs.join("\n"));

  const outputLineCount = $derived.by(() => {
    if (!stdout) return 0;
    const lines = stdout.split("\n");
    if (lines[lines.length - 1] === "") lines.pop();
    return lines.length;
  });
</script>

<div class="flex h-full min-h-0 flex-col bg-surface-0">
  <div
    class="flex h-8.25 flex-none items-stretch border-b border-border bg-surface-1"
  >
    {#snippet tab(
      id: "system" | "program",
      label: string,
      icon: "logs" | "term",
      badge: number,
      badgeRed: boolean,
    )}
      <button
        class="relative inline-flex items-center gap-1.5 border-r border-border px-3.5 text-[12px] transition-colors {terminalStore.activeTab ===
        id
          ? "bg-surface-0 text-text before:absolute before:inset-x-0 before:top-0 before:h-0.5 before:bg-primary before:content-['']"
          : 'text-text-faint hover:text-text-dim'}"
        onclick={() => terminalStore.setActiveTab(id)}
      >
        <Icon name={icon} class="h-3.5 w-3.5" />
        {label}
        {#if badge > 0}
          <span
            class="min-w-3.75 rounded-full px-1 py-px text-center font-mono text-[9px] {terminalStore.activeTab ===
            id
              ? 'bg-primary-soft text-primary'
              : 'bg-surface-3 text-text-faint'} {badgeRed ? 'text-red!' : ''}"
            >{badge}</span
          >
        {/if}
      </button>
    {/snippet}

    {@render tab(
      "system",
      "System",
      "logs",
      logStore.entries.length,
      logStore.errorCount > 0,
    )}
    {@render tab("program", "Output", "term", outputLineCount, false)}

    <div class="ml-auto flex items-center gap-0.5 pr-2">
      <IconButton
        name="trash"
        size="sm"
        title={`Clear ${terminalStore.activeTab === "system" ? "log" : "output"}`}
        onclick={() => terminalStore.clearActive()}
      />
    </div>
  </div>

  <div
    class="relative min-h-0 flex-1 overflow-hidden"
    class:hidden={terminalStore.activeTab !== "system"}
  >
    <div class="scroll-thin h-full overflow-auto py-2">
      {#if logStore.entries.length === 0}
        <div class="px-3.5 py-2 font-mono text-[11.5px] text-text-ghost">
          — system log empty · press Compile or Step —
        </div>
      {:else}
        {#each logStore.entries as l (l.id)}
          <div
            class="flex gap-2.5 px-3.5 py-px font-mono text-[11.5px] leading-4.5"
          >
            <span class="flex-none text-text-ghost">{l.ts}</span>
            <span
              class="w-14 flex-none text-[10px] font-semibold tracking-[0.4px] {tagColor[
                l.level
              ]}">{l.tag}</span
            >
            <span
              class="flex-1 whitespace-pre-wrap wrap-break-word {l.level ===
              'error'
                ? 'text-red'
                : 'text-text-dim'}">{l.msg}</span
            >
          </div>
        {/each}
      {/if}
    </div>
  </div>

  <div
    class="relative min-h-0 flex-1 overflow-hidden"
    class:hidden={terminalStore.activeTab !== "program"}
  >
    {#if cpuStore.cpuState}
      <Terminal
        outputBuffer={stdout}
        waitingForInput={cpuStore.status === "WaitingForInput"}
        onSubmitInput={(text: string) => cpuStore.submitInput(text)}
      />
    {:else}
      <div class="px-3.5 py-2 font-mono text-[11.5px] text-text-ghost">
        — no program loaded · press Compile —
      </div>
    {/if}
  </div>
</div>
