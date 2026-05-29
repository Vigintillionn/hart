<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { Terminal } from "@xterm/xterm";
  import { FitAddon } from "@xterm/addon-fit";
  import "@xterm/xterm/css/xterm.css";

  let {
    outputBuffer = "",
    waitingForInput = false,
    hideCursor = false,
    onSubmitInput = (text: string) => {},
  } = $props();

  let terminalContainer: HTMLDivElement;
  let term: Terminal;
  let fitAddon: FitAddon;

  let localInputBuffer = "";
  let lastOutputLength = 0;

  onMount(() => {
    term = new Terminal({
      theme: {
        background: "#1e1e1e",
        foreground: "#4af626",
        cursor: "#f57f17",
      },
      disableStdin: hideCursor,
      fontFamily: '"Courier New", Courier, monospace',
      fontSize: 14,
      cursorBlink: !hideCursor,
      convertEol: true,
    });

    fitAddon = new FitAddon();
    term.loadAddon(fitAddon);

    term.open(terminalContainer);
    fitAddon.fit();

    term.onData((data) => {
      if (!waitingForInput) return;

      const char = data;
      if (char === "\r") {
        term.write("\r\n");
        onSubmitInput(localInputBuffer);
        localLastBuffer = (outputBuffer || "") + localInputBuffer + "\n";
        localInputBuffer = "";
      } else if (char === "\x7F") {
        if (localInputBuffer.length > 0) {
          localInputBuffer = localInputBuffer.slice(0, -1);
          term.write("\b \b");
        }
      } else {
        localInputBuffer += char;
        term.write(char);
      }
    });

    const resizeObserver = new ResizeObserver(() => {
      if (
        terminalContainer.clientWidth > 0 &&
        terminalContainer.clientHeight > 0
      ) {
        fitAddon.fit();
      }
    });
    resizeObserver.observe(terminalContainer);

    return () => {
      resizeObserver.disconnect();
      term.dispose();
    };
  });

  let localLastBuffer = "";

  $effect(() => {
    if (term && outputBuffer !== undefined) {
      if (!outputBuffer.startsWith(localLastBuffer)) {
        term.reset();
        term.write(outputBuffer);
      } else if (outputBuffer.length > localLastBuffer.length) {
        const newText = outputBuffer.slice(localLastBuffer.length);
        term.write(newText);
      }
      localLastBuffer = outputBuffer;
    }
  });
</script>

<div
  class="w-full h-full p-4 box-border bg-zinc-950 overflow-hidden {hideCursor
    ? 'hide-cursor'
    : ''}"
  bind:this={terminalContainer}
></div>

<style>
  :global(.hide-cursor .xterm-cursor),
  :global(.hide-cursor .xterm-cursor-layer) {
    display: none !important;
    opacity: 0 !important;
    visibility: hidden !important;
  }
</style>
