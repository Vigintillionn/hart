<script lang="ts">
  import type { FileHandlers, OpenFile, SourceMap } from "$lib/types";
  import Monaco from "./Monaco.svelte";

  interface Props {
    openFiles: OpenFile[];
    setActiveFile: (id: string) => void;
    fileHandlers: FileHandlers;
    activeFileId: string;
    pc: number;
    sourceMap: SourceMap;
  }

  let {
    openFiles,
    setActiveFile,
    fileHandlers,
    activeFileId,
    pc,
    sourceMap,
  }: Props = $props();

  const handleEditorChange = (id: string, content: string) => {
    const file = openFiles.find((f) => f.id === id);
    if (file) {
      file.content = content;
    }
  };
</script>

<div class="flex bg-zinc-950 border-b border-zinc-800">
  {#each openFiles as file}
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="flex items-center gap-2 px-4 py-2 cursor-pointer text-sm border-r border-zinc-800 select-none {activeFileId ===
      file.id
        ? 'bg-zinc-900 text-white border-t-2 border-t-sky-500'
        : 'bg-zinc-950 text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900'}"
      onclick={() => setActiveFile(file.id)}
    >
      {file.name}
      {#if openFiles.length > 1}
        <button
          class="bg-transparent border-none text-zinc-500 hover:text-red-500 text-lg leading-none cursor-pointer p-0 m-0"
          onclick={(e) => fileHandlers.closeFile(file.id, e)}>×</button
        >
      {/if}
    </div>
  {/each}
</div>
<div class="flex-1 relative overflow-hidden">
  <Monaco
    {activeFileId}
    files={openFiles}
    onContentChange={handleEditorChange}
    currentPc={pc}
    {sourceMap}
  />
</div>
