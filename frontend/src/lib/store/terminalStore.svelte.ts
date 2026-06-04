import { TerminalState } from "../terminal.svelte";
import { logStore } from "./logStore.svelte";
import { loadJSON, saveJSON } from "../persist";

export type ConsoleTab = "system" | "program";

const TAB_KEY = "hart:consoleTab";
const CLEAR_KEY = "hart:clearOnRun";
const AUTOSWITCH_KEY = "hart:autoSwitchTabs";

export const DEFAULT_CLEAR_ON_RUN = false;
export const DEFAULT_AUTO_SWITCH = true;

class TerminalStore {
  activeTab = $state<ConsoleTab>(loadJSON<ConsoleTab>(TAB_KEY, "system"));
  program = new TerminalState();

  clearOnRun = $state(loadJSON(CLEAR_KEY, DEFAULT_CLEAR_ON_RUN));
  autoSwitchTabs = $state(loadJSON(AUTOSWITCH_KEY, DEFAULT_AUTO_SWITCH));

  constructor() {
    $effect.root(() => {
      $effect(() => saveJSON(TAB_KEY, this.activeTab));
      $effect(() => saveJSON(CLEAR_KEY, this.clearOnRun));
      $effect(() => saveJSON(AUTOSWITCH_KEY, this.autoSwitchTabs));
    });
  }

  public setActiveTab(tab: ConsoleTab) {
    this.activeTab = tab;
  }

  public autoSwitch(tab: ConsoleTab) {
    if (this.autoSwitchTabs) this.activeTab = tab;
  }

  public clearActive() {
    if (this.activeTab === "system") logStore.clear();
    else this.program.clear();
  }

  public resetPrefs() {
    this.clearOnRun = DEFAULT_CLEAR_ON_RUN;
    this.autoSwitchTabs = DEFAULT_AUTO_SWITCH;
  }
}

export const terminalStore = new TerminalStore();
