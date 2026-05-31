import type { PaneAPI } from "paneforge";

export const PANE_KEYS = {
  mainH: "hart-main-h", // [ editor+console | debug ]
  leftV: "hart-left-v", // [ editor / console ]
  debugV: "hart-debug-v", // [ registers / memory ]
} as const;

class LayoutStore {
  /** global HEX/DEC number base, shared by registers, memory & CPU header */
  hexMode = $state(true);

  isDebugVisible = $state(true);
  isConsoleVisible = $state(true);
  isRegistersVisible = $state(true);
  isMemoryVisible = $state(true);

  debugPaneRef = $state<PaneAPI>();
  consolePaneRef = $state<PaneAPI>();
  registersPaneRef = $state<PaneAPI>();
  memoryPaneRef = $state<PaneAPI>();

  public toggleDebug(visible: boolean) {
    if (visible) {
      this.debugPaneRef?.expand();
      if (!this.isRegistersVisible && !this.isMemoryVisible) {
        this.registersPaneRef?.expand();
        this.memoryPaneRef?.expand();
      }
    } else {
      this.debugPaneRef?.collapse();
    }
  }

  public toggleConsole(visible: boolean) {
    if (visible) this.consolePaneRef?.expand();
    else this.consolePaneRef?.collapse();
  }

  public toggleRegisters(visible: boolean) {
    if (visible) this.registersPaneRef?.expand();
    else if (!this.isMemoryVisible) this.toggleDebug(false);
    else this.registersPaneRef?.collapse();
  }

  public toggleMemory(visible: boolean) {
    if (visible) this.memoryPaneRef?.expand();
    else if (!this.isRegistersVisible) this.toggleDebug(false);
    else this.memoryPaneRef?.collapse();
  }

  public resetLayout() {
    for (const key of Object.values(PANE_KEYS)) {
      localStorage.removeItem(`paneforge:${key}`);
    }
    window.location.reload();
  }
}

export const layoutStore = new LayoutStore();
