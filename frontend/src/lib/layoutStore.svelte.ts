import type { PaneAPI } from "paneforge";

class LayoutStore {
  isCpuVisible = $state(true);
  isTerminalVisible = $state(true);
  isRegistersVisible = $state(true);
  isMemoryVisible = $state(true);

  cpuPaneRef = $state<PaneAPI>();
  terminalPaneRef = $state<PaneAPI>();
  registersPaneRef = $state<PaneAPI>();
  memoryPaneRef = $state<PaneAPI>();

  public toggleCpu(visible: boolean) {
    if (visible) {
      this.cpuPaneRef?.expand();
      if (!this.isRegistersVisible && !this.isMemoryVisible) {
        this.registersPaneRef?.expand();
        this.memoryPaneRef?.expand();
      }
    } else {
      this.cpuPaneRef?.collapse();
    }
  }

  public toggleTerminal(visible: boolean) {
    if (visible) this.terminalPaneRef?.expand();
    else this.terminalPaneRef?.collapse();
  }

  public toggleRegisters(visible: boolean) {
    if (visible) {
      this.registersPaneRef?.expand();
    } else {
      if (!this.isMemoryVisible) {
        this.toggleCpu(false);
      } else {
        this.registersPaneRef?.collapse();
      }
    }
  }

  public toggleMemory(visible: boolean) {
    if (visible) {
      this.memoryPaneRef?.expand();
    } else {
      if (!this.isRegistersVisible) {
        this.toggleCpu(false);
      } else {
        this.memoryPaneRef?.collapse();
      }
    }
  }

  public resetLayout() {
    localStorage.removeItem("paneforge:app-layout-vertical");
    localStorage.removeItem("paneforge:app-layout-horizontal");
    localStorage.removeItem("paneforge:debug-panel-layout");
    window.location.reload();
  }
}

export const layoutStore = new LayoutStore();
