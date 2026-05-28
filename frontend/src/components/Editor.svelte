<script lang="ts">
  import { fileStore } from "$lib/fileStore.svelte";
  import { cpuStore } from "$lib/cpuStore.svelte";
  import Monaco from "./Monaco.svelte";

  const handleEditorChange = (id: string, content: string) => {
    const file = fileStore.openFiles.find((f) => f.id === id);
    if (file) {
      file.content = content;
    }
  };
</script>

<div class="flex bg-zinc-950 border-b border-zinc-800">
  {#each fileStore.openFiles as file}
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="flex items-center gap-2 px-4 py-2 cursor-pointer text-sm border-r border-zinc-800 select-none {fileStore.activeFileId ===
      file.id
        ? 'bg-zinc-900 text-white border-t-2 border-t-sky-500'
        : 'bg-zinc-950 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900'}"
      onclick={() => fileStore.setActiveFileId(file.id)}
    >
      {file.name}
      {#if fileStore.openFiles.length > 1}
        <button
          class="bg-transparent border-none text-zinc-500 hover:text-red-500 text-lg leading-none cursor-pointer p-0 m-0"
          onclick={(e) => fileStore.closeFile(file.id, e)}>×</button
        >
      {/if}
    </div>
  {/each}
</div>
<div class="flex-1 relative overflow-hidden">
  <Monaco
    activeFileId={fileStore.activeFileId}
    files={fileStore.openFiles}
    onContentChange={handleEditorChange}
    currentPc={cpuStore.cpuState?.pc ?? 0}
    sourceMap={cpuStore.sourceMap}
  />
</div>
