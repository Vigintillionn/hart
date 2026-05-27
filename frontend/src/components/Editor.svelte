<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import * as monaco from 'monaco-editor';
  
  let { 
    code = $bindable(), 
    currentPc = 0, 
    sourceMap = [] as [number, number][] 
  } = $props();

  let editorContainer: HTMLDivElement;
  let editor: monaco.editor.IStandaloneCodeEditor;
  let decorationsCollection: monaco.editor.IEditorDecorationsCollection;

  let pcToLineMap = $derived(new Map(sourceMap));

  onMount(() => {
    editor = monaco.editor.create(editorContainer, {
      value: code,
      language: 'assembly', 
      theme: 'vs-dark',
      automaticLayout: true,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
    });

    editor.onDidChangeModelContent(() => {
      code = editor.getValue();
    });

    decorationsCollection = editor.createDecorationsCollection([]);
  });

  onDestroy(() => {
    if (editor) editor.dispose();
  });

  $effect(() => {
    if (editor && decorationsCollection) {
      const targetLine = pcToLineMap.get(currentPc) || 1;

      decorationsCollection.set([{
        range: new monaco.Range(targetLine, 1, targetLine, 1),
        options: {
          isWholeLine: true,
          className: 'pc-highlight-line', 
          glyphMarginClassName: 'pc-highlight-gutter'
        }
      }]);
      
      editor.revealLineInCenter(targetLine, monaco.editor.ScrollType.Smooth);
    }
  });
</script>

<div class="monaco-container" bind:this={editorContainer}></div>

<style global>
  .monaco-container {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    border-radius: 4px;
    overflow: hidden;
  }

  :global(.pc-highlight-line) {
    background-color: rgba(255, 255, 0, 0.2) !important;
  }

  :global(.pc-highlight-gutter) {
    background-color: #ffd700;
    border-radius: 50%;
    width: 10px !important;
    height: 10px !important;
    margin-left: 5px;
    margin-top: 4px;
  }
</style>
