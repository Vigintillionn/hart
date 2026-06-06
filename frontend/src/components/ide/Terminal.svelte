<script lang="ts">
  import { tick } from "svelte";

  let {
    outputBuffer = "",
    waitingForInput = false,
    filename = "program.s",
    exited = false,
    exitLabel = "",
    onSubmitInput = (_text: string) => {},
  }: {
    outputBuffer?: string;
    waitingForInput?: boolean;
    filename?: string;
    exited?: boolean;
    exitLabel?: string;
    onSubmitInput?: (text: string) => void;
  } = $props();

  let scrollEl = $state<HTMLDivElement>();
  let inputEl = $state<HTMLInputElement>();
  let draft = $state("");
  let pinned = true;

  function onScroll() {
    const el = scrollEl;
    if (!el) return;
    pinned = el.scrollHeight - el.scrollTop - el.clientHeight < 16;
  }

  // Keep the view pinned to the latest output (and the live input line).
  $effect(() => {
    void outputBuffer;
    void draft;
    void exited;
    if (!pinned) return;
    tick().then(() => {
      if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight;
    });
  });

  // Grab focus the moment the program asks for input.
  $effect(() => {
    if (waitingForInput) inputEl?.focus();
  });

  function onKeydown(e: KeyboardEvent) {
    if (e.key !== "Enter") return;
    e.preventDefault();
    if (!waitingForInput) return;
    onSubmitInput(draft);
    draft = "";
  }
</script>

<div class="flex h-full min-h-0 flex-col bg-surface-0 font-mono text-[12.5px]">
  <div
    class="flex-none truncate border-b border-border-soft px-3.5 py-1.5 text-[11px] text-text-faint"
  >
    hart · <span class="text-text-dim">./{filename}</span>
  </div>

  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div
    bind:this={scrollEl}
    onscroll={onScroll}
    onclick={() => inputEl?.focus()}
    class="min-h-0 flex-1 cursor-text overflow-auto px-3.5 py-2 leading-4.5"
  >
    <pre
      class="m-0 whitespace-pre-wrap wrap-break-word font-mono text-text">{outputBuffer}{#if waitingForInput}{draft}{/if}{#if !exited}<span
          class="term-caret"></span>{/if}</pre>
    {#if exited}
      <div class="mt-0.5 text-text-faint">[{exitLabel}]</div>
    {/if}

    <input
      bind:this={inputEl}
      bind:value={draft}
      onkeydown={onKeydown}
      disabled={!waitingForInput}
      spellcheck="false"
      autocomplete="off"
      aria-label="program input"
      class="absolute h-0 w-0 border-0 p-0 opacity-0"
    />
  </div>
</div>
