import { TerminalState } from "../terminal.svelte";
import { logStore } from "./logStore.svelte";

export type ConsoleTab = "system" | "program";

class TerminalStore {
  activeTab = $state<ConsoleTab>("system");
  program = new TerminalState();

  public setActiveTab(tab: ConsoleTab) {
    this.activeTab = tab;
  }

  public clearActive() {
    if (this.activeTab === "system") logStore.clear();
    else this.program.clear();
  }
}

export const terminalStore = new TerminalStore();
