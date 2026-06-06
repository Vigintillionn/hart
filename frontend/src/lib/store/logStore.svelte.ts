export type LogLevel = "info" | "exec" | "warn" | "error";

export interface LogEntry {
  id: number;
  ts: string;
  level: LogLevel;
  tag: string;
  msg: string;
}

class LogStore {
  entries = $state<LogEntry[]>([]);
  errorCount = $derived(this.entries.filter((e) => e.level === "error").length);

  #t0 = performance.now();
  #seq = 0;
  #stamp() {
    return ((performance.now() - this.#t0) / 1000).toFixed(3);
  }

  public log(level: LogLevel, tag: string, msg: string): number {
    const id = this.#seq++;
    this.entries.push({ id, ts: this.#stamp(), level, tag, msg });
    if (this.entries.length > 400) {
      this.entries = this.entries.slice(-400);
    }
    return id;
  }

  public update(id: number, msg: string) {
    const e = this.entries.find((x) => x.id === id);
    if (e) e.msg = msg;
  }

  public clear() {
    this.entries = [];
  }
}

export const logStore = new LogStore();
