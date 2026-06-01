<script lang="ts">
  import { onMount } from "svelte";
  import { Terminal } from "@xterm/xterm";
  import { FitAddon } from "@xterm/addon-fit";

  let {
    outputBuffer = "",
    waitingForInput = false,
    onSubmitInput = (_text: string) => {},
  }: {
    outputBuffer?: string;
    waitingForInput?: boolean;
    onSubmitInput?: (text: string) => void;
  } = $props();

  let terminalContainer: HTMLDivElement;
  let term: Terminal;
  let fitAddon: FitAddon;

  let localInputBuffer = "";

  onMount(() => {
    term = new Terminal({
      theme: {
        background: "#0d0d10", // surface-0
        foreground: "#e7e7ec", // text
        cursor: "#fdb515", // primary
        selectionBackground: "rgba(253, 181, 21, 0.14)", // primary soft
      },
      fontFamily: "'JetBrains Mono', ui-monospace, monospace",
      fontSize: 12.5,
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
  class="box-border h-full w-full overflow-hidden bg-surface-0 px-3.5 py-2"
  bind:this={terminalContainer}
></div>
