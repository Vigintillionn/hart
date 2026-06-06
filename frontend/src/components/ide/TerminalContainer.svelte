<script lang="ts">
  import { terminalStore } from "$lib/store/terminalStore.svelte";
  import { logStore } from "$lib/store/logStore.svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { fileStore } from "$lib/store/fileStore.svelte";
  import Terminal from "./Terminal.svelte";
  import Icon from "../Icon.svelte";
  import IconButton from "../ui/IconButton.svelte";
  import ScrollArea from "../ui/ScrollArea.svelte";

  const tagColor: Record<string, string> = {
    info: "text-secondary",
    exec: "text-secondary",
    warn: "text-primary",
    error: "text-red",
  };

  type Seg = { t: string; hot: boolean };
  function highlight(msg: string): Seg[] {
    const re = /0x[0-9a-fA-F]+|\b\d+\b/g;
    const segs: Seg[] = [];
    let last = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(msg))) {
      if (m.index > last)
        segs.push({ t: msg.slice(last, m.index), hot: false });
      segs.push({ t: m[0], hot: true });
      last = m.index + m[0].length;
    }
    if (last < msg.length) segs.push({ t: msg.slice(last), hot: false });
    return segs;
  }

  const stdout = $derived(terminalStore.program.logs.join("\n"));

  const exitInfo = $derived.by(() => {
    const st = cpuStore.cpuState;
    if (!st || st.status !== "Halted") return null;
    let label = "process halted";
    let faulted = false;
    for (const ev of st.systemLog) {
      if (ev.notice?.kind === "ProgramExitedNormally")
        label = "process exited with code 0";
      else if (ev.notice?.kind === "ProgramExited")
        label = `process exited with code ${ev.notice.code}`;
      if (ev.fault) faulted = true;
    }
    if (faulted && label === "process halted") label = "process terminated";
    return { label };
  });

  const outputLineCount = $derived.by(() => {
    if (!stdout) return 0;
    const lines = stdout.split("\n");
    if (lines[lines.length - 1] === "") lines.pop();
    return lines.length;
  });

  let systemScrollEl = $state<HTMLElement | undefined>();
  let systemPinned = true;
  let lastTab = terminalStore.activeTab;

  function onSystemScroll() {
    const el = systemScrollEl;
    if (!el) return;
    systemPinned = el.scrollHeight - el.scrollTop - el.clientHeight < 16;
  }

  $effect(() => {
    void logStore.entries.length; // re-run when a new entry arrives
    const tab = terminalStore.activeTab;
    const el = systemScrollEl;
    const switchedToSystem = tab === "system" && lastTab !== "system";
    lastTab = tab;
    if (tab !== "system" || !el) return;
    if (systemPinned || switchedToSystem) {
      el.scrollTop = el.scrollHeight;
      systemPinned = true;
    }
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
    <ScrollArea
      class="h-full"
      viewportClass="h-full py-2"
      bind:viewport={systemScrollEl}
      onscroll={onSystemScroll}
    >
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
              class="flex-1 whitespace-pre-wrap wrap-break-word text-text-dim"
              >{#each highlight(l.msg) as seg, i (i)}<span
                  class:text-text={seg.hot}
                  class:font-medium={seg.hot}>{seg.t}</span
                >{/each}</span
            >
          </div>
        {/each}
      {/if}
    </ScrollArea>
  </div>

  <div
    class="relative min-h-0 flex-1 overflow-hidden"
    class:hidden={terminalStore.activeTab !== "program"}
  >
    {#if cpuStore.cpuState}
      <Terminal
        outputBuffer={stdout}
        waitingForInput={cpuStore.status === "WaitingForInput"}
        filename={fileStore.activeFile.name}
        exited={exitInfo !== null}
        exitLabel={exitInfo?.label ?? ""}
        onSubmitInput={(text: string) => cpuStore.submitInput(text)}
      />
    {:else}
      <div class="px-3.5 py-2 font-mono text-[11.5px] text-text-ghost">
        — no program loaded · press Compile —
      </div>
    {/if}
  </div>
</div>
