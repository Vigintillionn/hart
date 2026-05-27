<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { Terminal } from "@xterm/xterm";
  import { FitAddon } from "@xterm/addon-fit";
  import "@xterm/xterm/css/xterm.css";

  let {
    outputBuffer = "",
    waitingForInput = false,
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
      fontFamily: '"Courier New", Courier, monospace',
      fontSize: 14,
      cursorBlink: true,
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
        // Enter pressed
        term.write("\r\n");
        onSubmitInput(localInputBuffer);
        // Preemptively update localLastBuffer to prevent double-printing
        // when the backend echoes this input back to us!
        localLastBuffer = (outputBuffer || "") + localInputBuffer + "\n";
        localInputBuffer = "";
      } else if (char === "\x7F") {
        // Backspace
        if (localInputBuffer.length > 0) {
          localInputBuffer = localInputBuffer.slice(0, -1);
          term.write("\b \b");
        }
      } else {
        // Normal char
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
        // Buffer was reset or altered destructively (e.g., Rewind)
        term.reset();
        term.write(outputBuffer);
      } else if (outputBuffer.length > localLastBuffer.length) {
        // Append only the new output
        const newText = outputBuffer.slice(localLastBuffer.length);
        term.write(newText);
      }
      localLastBuffer = outputBuffer;
    }
  });
</script>

<div class="terminal-container" bind:this={terminalContainer}></div>

<style>
  .terminal-container {
    width: 100%;
    height: 100%;
    padding: 16px;
    box-sizing: border-box;
    background: #1e1e1e;
    overflow: hidden;
  }
</style>
