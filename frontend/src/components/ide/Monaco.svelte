<script lang="ts">
  import { onMount, onDestroy } from "svelte";
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
    breakpoints = new Set<number>(),
    onToggleBreakpoint = (_line: number) => {},
    readOnly = false,
  }: {
    activeFileId?: string;
    files?: Pick<OpenFile, "id" | "content">[];
    onContentChange?: (id: string, newContent: string) => void;
    currentPc?: number;
    pcToLine?: Map<number, number>;
    breakpoints?: Set<number>;
    onToggleBreakpoint?: (line: number) => void;
    readOnly?: boolean;
  } = $props();

  let editorContainer: HTMLDivElement;
  let editor: monaco.editor.IStandaloneCodeEditor;
  let decorationsCollection: monaco.editor.IEditorDecorationsCollection;
  let breakpointDecorations: monaco.editor.IEditorDecorationsCollection;
  let hoverDecorations: monaco.editor.IEditorDecorationsCollection;
  let models = new Map<string, monaco.editor.ITextModel>();

  const currentLine = $derived(pcToLine.get(currentPc) || 0);
  let lastLine = 0;
  let fadeTimer: number;

  const breakpointableLines = $derived(new Set(pcToLine.values()));
  let hoverLine = $state<number | null>(null);

  const activeContent = $derived(
    files.find((f) => f.id === activeFileId)?.content ?? "",
  );
  const ebreakLines = $derived.by(() => {
    const set = new Set<number>();
    activeContent.split("\n").forEach((raw, i) => {
      const code = raw.split("#")[0]; // ignore line comments
      if (/\bebreak\b/i.test(code)) set.add(i + 1);
    });
    return set;
  });

  if (typeof self !== "undefined") {
    self.MonacoEnvironment = {
      getWorker: () => new editorWorker(),
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
      lineNumbersMinChars: 3,
      lineDecorationsWidth: 6,
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
    breakpointDecorations = editor.createDecorationsCollection([]);
    hoverDecorations = editor.createDecorationsCollection([]);

    editor.onMouseDown((e) => {
      if (e.target.type === monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN) {
        const line = e.target.position?.lineNumber;
        if (line && !ebreakLines.has(line)) onToggleBreakpoint(line);
      }
    });

    editor.onMouseMove((e) => {
      let next: number | null = null;
      if (e.target.type === monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN) {
        const line = e.target.position?.lineNumber;
        if (
          line &&
          breakpointableLines.has(line) &&
          !breakpoints.has(line) &&
          !ebreakLines.has(line)
        ) {
          next = line;
        }
      }
      if (next !== hoverLine) hoverLine = next;
    });
    editor.onMouseLeave(() => {
      if (hoverLine !== null) hoverLine = null;
    });

    document.fonts?.ready.then(() => monaco.editor.remeasureFonts());
  });

  $effect(() => {
    editor?.updateOptions({ readOnly });
  });

  onDestroy(() => {
    if (editor) editor.dispose();
    for (const model of models.values()) {
      model.dispose();
    }
    clearTimeout(fadeTimer);
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

  function currentLineDecoration(
    line: number,
  ): monaco.editor.IModelDeltaDecoration {
    return {
      range: new monaco.Range(line, 1, line, 1),
      options: {
        isWholeLine: true,
        className: "pc-highlight-line",
      },
    };
  }

  $effect(() => {
    const line = currentLine;
    const pc = currentPc;
    if (!editor || !decorationsCollection) return;

    clearTimeout(fadeTimer);

    if (!line) {
      decorationsCollection.clear();
      lastLine = 0;
      return;
    }

    const decs = [currentLineDecoration(line)];

    if (lastLine && lastLine !== line && pc !== 0) {
      decs.push({
        range: new monaco.Range(lastLine, 1, lastLine, 1),
        options: { isWholeLine: true, className: "pc-previous-line" },
      });
      const settled = line;
      fadeTimer = window.setTimeout(
        () => decorationsCollection.set([currentLineDecoration(settled)]),
        1500,
      );
    }

    decorationsCollection.set(decs);
    if (pc > 0) {
      editor.revealLineInCenter(line, monaco.editor.ScrollType.Smooth);
    }
    lastLine = line;
  });

  function breakpointDecoration(
    line: number,
    ebreak: boolean,
  ): monaco.editor.IModelDeltaDecoration {
    return {
      range: new monaco.Range(line, 1, line, 1),
      options: {
        glyphMarginClassName: ebreak
          ? "breakpoint-glyph breakpoint-glyph-ebreak"
          : "breakpoint-glyph",
        glyphMarginHoverMessage: {
          value: ebreak ? "Breakpoint (`ebreak`)" : "Breakpoint",
        },
        stickiness:
          monaco.editor.TrackedRangeStickiness.NeverGrowsWhenTypingAtEdges,
      },
    };
  }

  $effect(() => {
    void activeFileId;
    if (!editor || !breakpointDecorations) return;
    const decs: monaco.editor.IModelDeltaDecoration[] = [];
    for (const line of breakpoints)
      decs.push(breakpointDecoration(line, false));
    for (const line of ebreakLines) {
      if (!breakpoints.has(line)) decs.push(breakpointDecoration(line, true));
    }
    breakpointDecorations.set(decs);
  });

  $effect(() => {
    if (!editor || !hoverDecorations) return;
    const line = hoverLine;
    const show =
      line !== null && !breakpoints.has(line) && !ebreakLines.has(line);
    hoverDecorations.set(
      show && line !== null
        ? [
            {
              range: new monaco.Range(line, 1, line, 1),
              options: { glyphMarginClassName: "breakpoint-glyph-hover" },
            },
          ]
        : [],
    );
  });
</script>

<div
  class="absolute inset-0 w-full h-full rounded-md overflow-hidden"
  bind:this={editorContainer}
></div>
