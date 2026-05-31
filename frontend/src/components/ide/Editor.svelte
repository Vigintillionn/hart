<script lang="ts">
  import { fileStore } from "$lib/store/fileStore.svelte";
  import { cpuStore } from "$lib/store/cpuStore.svelte";
  import Monaco from "./Monaco.svelte";
  import Icon from "../Icon.svelte";

  const handleEditorChange = (id: string, content: string) => {
    const file = fileStore.openFiles.find((f) => f.id === id);
    if (file) file.content = content;
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
      <!-- svelte-ignore a11y_click_events_have_key_events -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="relative flex h-9 cursor-default select-none items-center gap-2 border-r border-border px-4 text-[12.5px] transition-colors {fileStore.activeFileId ===
        file.id
          ? "bg-surface-0 text-text before:absolute before:inset-x-0 before:top-0 before:h-0.5 before:bg-primary before:content-['']"
          : 'text-text-dim hover:text-text'}"
        onclick={() => fileStore.setActiveFileId(file.id)}
      >
        <span>{parts.base}<span class="text-secondary">{parts.ext}</span></span>
        {#if fileStore.openFiles.length > 1}
          <button
            class="text-text-faint transition-colors hover:text-red"
            onclick={(e) => fileStore.closeFile(file.id, e)}
            title="Close">×</button
          >
        {/if}
      </div>
    {/each}

    <div
      class="ml-auto flex items-center gap-1.5 pr-4 font-mono text-[10.5px] tracking-[0.3px] text-text-faint"
    >
      {#if running}
        <Icon name="lock" class="h-3 w-3" /> running · read-only
      {:else}
        <Icon name="pencil" class="h-3 w-3" /> editable · RV32I
      {/if}
    </div>
  </div>

  <div class="relative min-h-0 flex-1 overflow-hidden">
    <Monaco
      activeFileId={fileStore.activeFileId}
      files={fileStore.openFiles}
      onContentChange={handleEditorChange}
      currentPc={cpuStore.cpuState?.pc ?? 0}
      sourceMap={cpuStore.sourceMap}
      readOnly={running}
    />
  </div>
</div>
