export class TerminalState {
  id = $state("");
  logs = $state<string[]>([]);

  constructor(id: string) {
    this.id = id;
  }

  public log(message: string) {
    this.logs.push(message);
  }

  public set(message: string) {
    this.logs = [message];
  }

  public clear() {
    this.logs = [];
  }
}
