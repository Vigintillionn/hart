import { TerminalState } from "../terminal.svelte";
import { logStore } from "./logStore.svelte";
import { loadJSON, saveJSON } from "../persist";

export type ConsoleTab = "system" | "program";

const TAB_KEY = "hart:consoleTab";

class TerminalStore {
  activeTab = $state<ConsoleTab>(loadJSON<ConsoleTab>(TAB_KEY, "system"));
  program = new TerminalState();

  constructor() {
    $effect.root(() => {
      $effect(() => saveJSON(TAB_KEY, this.activeTab));
    });
  }

  public setActiveTab(tab: ConsoleTab) {
    this.activeTab = tab;
  }

  public clearActive() {
    if (this.activeTab === "system") logStore.clear();
    else this.program.clear();
  }
}

export const terminalStore = new TerminalStore();
