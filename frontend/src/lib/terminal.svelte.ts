export class TerminalState {
  logs = $state<string[]>([]);

  public set(message: string) {
    this.logs = [message];
  }

  public clear() {
    this.logs = [];
  }
}
