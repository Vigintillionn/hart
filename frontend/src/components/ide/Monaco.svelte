<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import * as monaco from "monaco-editor";
  import editorWorker from "monaco-editor/esm/vs/editor/editor.worker?worker";
  import {
    buildRiscvLanguageDef,
    riscvLanguageConfig,
  } from "../../lib/editor/riscvMonarch";
  import { registerRiscvHover } from "../../lib/editor/riscvHover";
  import { activeTheme } from "../../lib/editor/theme.svelte";
  import { modeStore } from "../../lib/store/mode.svelte";
  import { editorPrefs, fontStack } from "../../lib/store/editorPrefs.svelte";
  import { isaStore } from "../../lib/store/isaStore.svelte";
  import { extensionStore } from "../../lib/store/extensionStore.svelte";
  import { REGISTERS } from "../../lib/store/helpCatalogue.svelte";
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
    errorMarker = null,
  }: {
    activeFileId?: string;
    files?: Pick<OpenFile, "id" | "content">[];
    onContentChange?: (id: string, newContent: string) => void;
    currentPc?: number;
    pcToLine?: Map<number, number>;
    breakpoints?: Set<number>;
    onToggleBreakpoint?: (line: number) => void;
    readOnly?: boolean;
    errorMarker?: {
      fileId: string;
      line: number | null;
      message: string;
    } | null;
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

  const REGISTER_NAMES: string[] = (() => {
    const set = new Set<string>();
    for (const r of REGISTERS) {
      set.add(r.arch);
      for (const name of r.abi.split("/")) set.add(name);
    }
    return [...set];
  })();

  const CSR_NAMES = $derived(isaStore.csrs.map((c) => c.name));

  const keywords = $derived.by(() => {
    const haveExtensions = extensionStore.catalogue.length > 0;
    const enabled = new Set(extensionStore.enabledCodes);
    const set = new Set<string>();
    for (const i of isaStore.instructions)
      if (!haveExtensions || enabled.has(i.extension)) set.add(i.mnemonic);
    for (const p of isaStore.pseudos)
      if (!haveExtensions || enabled.has(p.extension)) set.add(p.mnemonic);
    return [...set];
  });

  const disabledMnemonics = $derived.by(() => {
    const map = new Map<string, string>();
    if (extensionStore.catalogue.length === 0) return map;
    const enabled = new Set(extensionStore.enabledCodes);
    for (const i of isaStore.instructions)
      if (!enabled.has(i.extension)) map.set(i.mnemonic, i.extension);
    for (const p of isaStore.pseudos)
      if (!enabled.has(p.extension)) map.set(p.mnemonic, p.extension);
    return map;
  });

  let languageReady = $state(false);
  let tokensProvider: monaco.IDisposable | undefined;

  if (typeof self !== "undefined") {
    self.MonacoEnvironment = {
      getWorker: () => new editorWorker(),
    };
  }

  onMount(() => {
    monaco.languages.register({ id: "riscv" });
    monaco.languages.setLanguageConfiguration("riscv", riscvLanguageConfig);
    registerRiscvHover(monaco);

    editor = monaco.editor.create(editorContainer, {
      language: "riscv",
      theme: "vs-dark",
      automaticLayout: true,
      minimap: { enabled: editorPrefs.minimap },
      scrollBeyondLastLine: false,
      glyphMargin: true,
      lineNumbersMinChars: 3,
      lineDecorationsWidth: 6,
      fontFamily: fontStack(editorPrefs.fontFamily),
      fontSize: editorPrefs.fontSize,
      lineNumbers: editorPrefs.lineNumbers,
      wordWrap: editorPrefs.wordWrap ? "on" : "off",
      renderWhitespace: editorPrefs.renderWhitespace ? "all" : "none",
      renderControlCharacters: editorPrefs.renderWhitespace,
      detectIndentation: false,
      tabSize: editorPrefs.tabWidth,
      insertSpaces: editorPrefs.insertSpaces,
      lineHeight: 0,
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

    languageReady = true;
  });

  $effect(() => {
    const kws = keywords;
    const regs = REGISTER_NAMES;
    const csrs = CSR_NAMES;
    if (!languageReady) return;
    tokensProvider?.dispose();
    tokensProvider = monaco.languages.setMonarchTokensProvider(
      "riscv",
      buildRiscvLanguageDef(kws, regs, csrs),
    );
  });

  $effect(() => {
    editor?.updateOptions({ readOnly });
  });

  let lastFontFamily = editorPrefs.fontFamily;
  $effect(() => {
    const family = editorPrefs.fontFamily;
    if (!editor) return;
    editor.updateOptions({
      fontFamily: fontStack(family),
      fontSize: editorPrefs.fontSize,
      lineNumbers: editorPrefs.lineNumbers,
      wordWrap: editorPrefs.wordWrap ? "on" : "off",
      renderWhitespace: editorPrefs.renderWhitespace ? "all" : "none",
      renderControlCharacters: editorPrefs.renderWhitespace,
      minimap: { enabled: editorPrefs.minimap },
    });
    const tabSize = editorPrefs.tabWidth;
    const insertSpaces = editorPrefs.insertSpaces;
    for (const model of models.values())
      model.updateOptions({ tabSize, insertSpaces });
    if (family !== lastFontFamily) {
      lastFontFamily = family;
      document.fonts?.ready.then(() => monaco.editor.remeasureFonts());
    }
  });

  onDestroy(() => {
    tokensProvider?.dispose();
    if (editor) editor.dispose();
    for (const model of models.values()) {
      model.dispose();
    }
    clearTimeout(fadeTimer);
  });

  $effect(() => {
    if (editor) {
      const t = activeTheme();
      monaco.editor.defineTheme("riscv-theme", {
        base: modeStore.mode === "light" ? "vs" : "vs-dark",
        inherit: true,
        rules: [
          { token: "custom-keyword", foreground: t.keyword },
          { token: "custom-register", foreground: t.register },
          { token: "custom-csr", foreground: t.csr },
          { token: "custom-directive", foreground: t.directive },
          { token: "custom-number", foreground: t.number },
          { token: "custom-comment", foreground: t.comment },
          { token: "custom-string", foreground: t.string },
          { token: "custom-string.quote", foreground: t.string },
          { token: "custom-string.escape", foreground: t.string },
        ],
        colors: {
          "editor.background": t.background,
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
          newModel.updateOptions({
            tabSize: editorPrefs.tabWidth,
            insertSpaces: editorPrefs.insertSpaces,
          });
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
        lineNumberClassName: "pc-highlight-line-number",
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
    const marker = errorMarker;
    const fileId = activeFileId;
    if (!editor) return;
    const model = fileId ? models.get(fileId) : editor.getModel();
    if (!model) return;

    if (!marker || marker.line === null || marker.fileId !== fileId) {
      monaco.editor.setModelMarkers(model, "hart", []);
      return;
    }

    const line = Math.min(Math.max(marker.line, 1), model.getLineCount());
    monaco.editor.setModelMarkers(model, "hart", [
      {
        startLineNumber: line,
        startColumn: 1,
        endLineNumber: line,
        endColumn: model.getLineMaxColumn(line),
        message: marker.message,
        severity: monaco.MarkerSeverity.Error,
      },
    ]);
    editor.revealLineInCenterIfOutsideViewport(
      line,
      monaco.editor.ScrollType.Smooth,
    );
  });

  $effect(() => {
    const disabled = disabledMnemonics;
    const content = activeContent;
    const fileId = activeFileId;
    if (!languageReady) return;
    const model = fileId ? models.get(fileId) : editor.getModel();
    if (!model) return;

    const markers: monaco.editor.IMarkerData[] = [];
    if (disabled.size) {
      content.split("\n").forEach((raw, i) => {
        const code = raw.split("#")[0].split("//")[0];
        const m = code.match(/^\s*(?:[A-Za-z_]\w*\s*:\s*)?([A-Za-z]\w*)/);
        if (!m) return;
        const ext = disabled.get(m[1]);
        if (!ext) return;
        const startColumn = m[0].length - m[1].length + 1;
        markers.push({
          startLineNumber: i + 1,
          startColumn,
          endLineNumber: i + 1,
          endColumn: startColumn + m[1].length,
          message: `\`${m[1]}\` requires the ${ext} extension, which is disabled`,
          severity: monaco.MarkerSeverity.Error,
        });
      });
    }
    monaco.editor.setModelMarkers(model, "hart-ext", markers);
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
