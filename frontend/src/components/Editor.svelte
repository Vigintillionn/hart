<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as monaco from "monaco-editor";
  import editorWorker from "monaco-editor/esm/vs/editor/editor.worker?worker";
  import { riscvLanguageDef } from "../lib/riscvMonarch";
  import { themeColors } from "../lib/theme.svelte";

  let {
    activeFileId = "",
    files = [] as { id: string; content: string }[],
    onContentChange = (id: string, newContent: string) => {},
    currentPc = 0,
    sourceMap = [] as [number, number][],
  } = $props();

  let editorContainer: HTMLDivElement;
  let editor: monaco.editor.IStandaloneCodeEditor;
  let decorationsCollection: monaco.editor.IEditorDecorationsCollection;
  let models = new Map<string, monaco.editor.ITextModel>();

  let pcToLineMap = $derived(new Map(sourceMap));

  if (typeof self !== "undefined") {
    self.MonacoEnvironment = {
      getWorker: function (_moduleId: any, label: string) {
        return new editorWorker();
      },
    };
  }

  onMount(() => {
    monaco.languages.register({ id: "riscv" });
    monaco.languages.setMonarchTokensProvider("riscv", riscvLanguageDef);

    editor = monaco.editor.create(editorContainer, {
      language: "riscv",
      theme: "vs-dark",
      automaticLayout: true,
      minimap: { enabled: false },
      scrollBeyondLastLine: false,
    });

    decorationsCollection = editor.createDecorationsCollection([]);
  });

  onDestroy(() => {
    if (editor) editor.dispose();
    for (const model of models.values()) {
      model.dispose();
    }
  });

  $effect(() => {
    if (editor) {
      monaco.editor.defineTheme("riscv-theme", {
        base: "vs-dark",
        inherit: true,
        rules: [
          { token: "custom-keyword", foreground: themeColors.keyword },
          { token: "custom-register", foreground: themeColors.register },
          { token: "custom-directive", foreground: themeColors.directive },
          { token: "custom-number", foreground: themeColors.number },
          { token: "custom-comment", foreground: themeColors.comment },
          { token: "custom-string", foreground: themeColors.string },
          { token: "custom-string.quote", foreground: themeColors.string },
          { token: "custom-string.escape", foreground: themeColors.string },
        ],
        colors: {
          "editor.background": themeColors.background,
        },
      });
      monaco.editor.setTheme("riscv-theme");
    }
  });

  $effect(() => {
    if (editor && activeFileId && files) {
      // Create models for new files
      for (const file of files) {
        if (!models.has(file.id)) {
          const newModel = monaco.editor.createModel(file.content, "riscv");
          newModel.onDidChangeContent(() => {
            onContentChange(file.id, newModel.getValue());
          });
          models.set(file.id, newModel);
        }
      }

      // Cleanup closed files
      for (const [id, model] of models.entries()) {
        if (!files.find((f) => f.id === id)) {
          model.dispose();
          models.delete(id);
        }
      }

      const targetModel = models.get(activeFileId);
      if (targetModel && editor.getModel() !== targetModel) {
        editor.setModel(targetModel);
      }
    }
  });

  $effect(() => {
    const targetLine = pcToLineMap.get(currentPc) || 0;

    if (editor && decorationsCollection && targetLine) {
      decorationsCollection.set([
        {
          range: new monaco.Range(targetLine, 1, targetLine, 1),
          options: {
            isWholeLine: true,
            className: "pc-highlight-line",
            glyphMarginClassName: "pc-highlight-gutter",
          },
        },
      ]);

      if (currentPc > 0) {
        editor.revealLineInCenter(targetLine, monaco.editor.ScrollType.Smooth);
      }
    }
  });
</script>

<div
  class="absolute inset-0 w-full h-full rounded-md overflow-hidden"
  bind:this={editorContainer}
></div>
