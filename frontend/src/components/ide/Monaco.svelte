<script lang="ts">
  import { onMount, onDestroy, untrack } from "svelte";
  import * as monaco from "monaco-editor";
  import editorWorker from "monaco-editor/esm/vs/editor/editor.worker?worker";
  import { riscvLanguageDef } from "../../lib/editor/riscvMonarch";
  import { themeColors } from "../../lib/editor/theme.svelte";
  import type { OpenFile } from "$lib/types";

  let {
    activeFileId = "",
    files = [],
    onContentChange = (_id: string, _newContent: string) => {},
    currentPc = 0,
    pcToLine = new Map<number, number>(),
    readOnly = false,
  }: {
    activeFileId?: string;
    files?: Pick<OpenFile, "id" | "content">[];
    onContentChange?: (id: string, newContent: string) => void;
    currentPc?: number;
    pcToLine?: Map<number, number>;
    readOnly?: boolean;
  } = $props();

  let editorContainer: HTMLDivElement;
  let editor: monaco.editor.IStandaloneCodeEditor;
  let decorationsCollection: monaco.editor.IEditorDecorationsCollection;
  let models = new Map<string, monaco.editor.ITextModel>();

  let previousPc = $state<number | null>(null);
  let oldPcVal = -1;
  let clearPrevPcTimeout: number;

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
      glyphMargin: true,
      fontFamily: "'JetBrains Mono', ui-monospace, monospace",
      fontSize: 13,
      lineHeight: 21,
      letterSpacing: 0,
      padding: { top: 12, bottom: 12 },
      renderLineHighlight: "none",
      smoothScrolling: true,
      cursorBlinking: "smooth",
      scrollbar: { verticalScrollbarSize: 9, horizontalScrollbarSize: 9 },
    });

    decorationsCollection = editor.createDecorationsCollection([]);
  });

  $effect(() => {
    editor?.updateOptions({ readOnly });
  });

  onDestroy(() => {
    if (editor) editor.dispose();
    for (const model of models.values()) {
      model.dispose();
    }
    clearTimeout(clearPrevPcTimeout);
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
      for (const file of files) {
        if (!models.has(file.id)) {
          const newModel = monaco.editor.createModel(file.content, "riscv");
          newModel.onDidChangeContent(() => {
            onContentChange(file.id, newModel.getValue());
          });
          models.set(file.id, newModel);
        }
      }

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
    const pc = currentPc;
    untrack(() => {
      if (pc !== oldPcVal) {
        previousPc = oldPcVal;
        oldPcVal = pc;

        clearTimeout(clearPrevPcTimeout);
        if (previousPc !== -1) {
          clearPrevPcTimeout = window.setTimeout(() => {
            previousPc = -1;
          }, 1500);
        }
      }
    });
  });

  $effect(() => {
    const targetLine = pcToLine.get(currentPc) || 0;
    const prevLine = previousPc !== null ? pcToLine.get(previousPc) || 0 : 0;

    if (editor && decorationsCollection && targetLine) {
      const decs: monaco.editor.IModelDeltaDecoration[] = [
        {
          range: new monaco.Range(targetLine, 1, targetLine, 1),
          options: {
            isWholeLine: true,
            className: "pc-highlight-line",
            glyphMarginClassName: "pc-highlight-gutter",
          },
        },
      ];

      if (
        prevLine &&
        prevLine !== targetLine &&
        previousPc !== -1 &&
        currentPc !== 0
      ) {
        decs.push({
          range: new monaco.Range(prevLine, 1, prevLine, 1),
          options: {
            isWholeLine: true,
            className: "pc-previous-line",
          },
        });
      }

      decorationsCollection.set(decs);

      if (currentPc > 0) {
        editor.revealLineInCenter(targetLine, monaco.editor.ScrollType.Smooth);
      }
    } else if (editor && decorationsCollection) {
      decorationsCollection.clear();
    }
  });
</script>

<div
  class="absolute inset-0 w-full h-full rounded-md overflow-hidden"
  bind:this={editorContainer}
></div>
