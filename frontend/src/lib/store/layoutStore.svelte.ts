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

  public toggleDebug() {
    if (this.debugPaneRef?.isCollapsed()) {
      this.debugPaneRef.expand();
      if (
        this.registersPaneRef?.isCollapsed() &&
        this.memoryPaneRef?.isCollapsed()
      ) {
        this.registersPaneRef?.expand();
        this.memoryPaneRef?.expand();
      }
    } else {
      this.debugPaneRef?.collapse();
    }
  }

  public toggleConsole() {
    if (this.consolePaneRef?.isCollapsed()) this.consolePaneRef.expand();
    else this.consolePaneRef?.collapse();
  }

  public toggleRegisters() {
    if (this.registersPaneRef?.isCollapsed()) this.registersPaneRef.expand();
    else if (this.memoryPaneRef?.isCollapsed()) this.debugPaneRef?.collapse();
    else this.registersPaneRef?.collapse();
  }

  public toggleMemory() {
    if (this.memoryPaneRef?.isCollapsed()) this.memoryPaneRef.expand();
    else if (this.registersPaneRef?.isCollapsed())
      this.debugPaneRef?.collapse();
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
