import { TerminalState } from "./terminal.svelte";

export const terminalStore = $state({
  activeTab: "system",
  system: new TerminalState("system"),
  program: new TerminalState("program"),

  setActiveTab(tab: "system" | "program") {
    this.activeTab = tab;
  },
});
