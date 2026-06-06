<script lang="ts">
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import { extensionStore } from "$lib/store/extensionStore.svelte";
  import Monaco from "./Monaco.svelte";
  import Icon from "../Icon.svelte";

  const handleEditorChange = (id: string, content: string) => {
    const file = fileStore.openFiles.find((f) => f.id === id);
    if (file) file.content = content;
    if (cpuStore.compileError) cpuStore.compileError = null;
  };

  const splitName = (name: string) => {
    const dot = name.lastIndexOf(".");
    return dot > 0
      ? { base: name.slice(0, dot), ext: name.slice(dot) }
      : { base: name, ext: "" };
  };

  const running = $derived(cpuStore.status === "Running");
</script>

<div class="flex h-full min-w-0 flex-col bg-surface-0">
  <div
    class="flex h-9 flex-none items-center border-b border-border bg-surface-1 pl-1"
  >
    {#each fileStore.openFiles as file (file.id)}
      {@const parts = splitName(file.name)}
      {@const dirty = fileStore.isDirty(file)}
      <div
        class="group relative flex h-9 select-none items-center border-r border-border text-[12.5px] transition-colors {fileStore.activeFileId ===
        file.id
          ? "bg-surface-0 text-text before:absolute before:inset-x-0 before:top-0 before:h-0.5 before:bg-primary before:content-['']"
          : 'text-text-dim hover:text-text'}"
      >
        <button
          class="flex h-full items-center gap-2 pl-4 pr-1.5"
          title={file.name}
          onclick={() => fileStore.setActiveFileId(file.id)}
        >
          <span
            >{parts.base}<span class="text-secondary">{parts.ext}</span></span
          >
          {#if dirty}
            <span
              class="h-1.5 w-1.5 flex-none rounded-full bg-primary group-hover:hidden"
              title="unsaved changes"
            ></span>
          {/if}
        </button>
        <button
          class="pr-3.5 pl-0.5 text-text-faint transition-colors hover:text-red {dirty
            ? 'hidden group-hover:block'
            : ''}"
          title="Close"
          onclick={(e) => fileStore.closeFile(file.id, e)}>×</button
        >
      </div>
    {/each}

    <button
      class="flex h-9 w-8 flex-none items-center justify-center text-base text-text-faint transition-colors hover:text-text"
      title="New file"
      onclick={() => fileStore.newFile()}>+</button
    >

    <div
      class="ml-auto flex items-center gap-1.5 pr-4 font-mono text-[10.5px] tracking-[0.3px] text-text-faint"
    >
      {#if running}
        <Icon name="lock" class="h-3 w-3" /> running · read-only
      {:else}
        <Icon name="pencil" class="h-3 w-3" /> editable · {extensionStore.isaString}
      {/if}
    </div>
  </div>

  <div class="relative min-h-0 flex-1 overflow-hidden">
    {#if fileStore.hasFiles}
      <Monaco
        activeFileId={fileStore.activeFileId}
        files={fileStore.openFiles}
        onContentChange={handleEditorChange}
        currentPc={cpuStore.cpuState?.pc ?? 0}
        pcToLine={cpuStore.sourceLineMap}
        breakpoints={cpuStore.breakpointLines}
        onToggleBreakpoint={(line) => cpuStore.toggleBreakpointLine(line)}
        readOnly={running}
        errorMarker={cpuStore.compileError}
      />
    {:else}
      <div
        class="flex h-full flex-col items-center justify-center gap-4 text-center"
      >
        <p class="text-[13px] text-text-dim">No files open</p>
        <div class="flex items-center gap-2">
          <button
            class="flex items-center gap-1.5 rounded-md border border-border bg-surface-1 px-3 py-1.5 text-[12px] text-text transition-colors hover:bg-surface-2"
            onclick={() => fileStore.newFile()}
          >
            <span class="text-base leading-none">+</span> New file
          </button>
          <button
            class="flex items-center gap-1.5 rounded-md border border-border bg-surface-1 px-3 py-1.5 text-[12px] text-text transition-colors hover:bg-surface-2"
            onclick={() => fileStore.handleOpenFile()}
          >
            <Icon name="folder" class="h-3.5 w-3.5" /> Open file…
          </button>
        </div>
      </div>
    {/if}
  </div>
</div>
