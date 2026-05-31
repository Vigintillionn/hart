export type LogLevel = "info" | "exec" | "warn" | "error";

export interface LogEntry {
  ts: string;
  level: LogLevel;
  tag: string;
  msg: string;
}

class LogStore {
  entries = $state<LogEntry[]>([]);
  errorCount = $derived(this.entries.filter((e) => e.level === "error").length);

  #t0 = performance.now();
  #stamp() {
    return ((performance.now() - this.#t0) / 1000).toFixed(3);
  }

  public log(level: LogLevel, tag: string, msg: string) {
    this.entries.push({ ts: this.#stamp(), level, tag, msg });
    if (this.entries.length > 400) {
      this.entries = this.entries.slice(-400);
    }
  }

  public clear() {
    this.entries = [];
  }
}

export const logStore = new LogStore();
