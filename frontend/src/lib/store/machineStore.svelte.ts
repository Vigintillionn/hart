import { loadJSON, saveJSON } from "../persist";
import { sendToHaskell } from "../util";

const STORAGE_KEY = "hart:machine";

export const HISTORY_PRESETS = [1_000, 10_000, 50_000, 100_000] as const;

export const HISTORY_MIN = 100;
export const HISTORY_MAX = 10_000_000;

export const HISTORY_DISCLAIMER = 100_000;

export const DEFAULT_HISTORY_SIZE = 10_000;

export function clampHistory(n: unknown): number {
  const v = Math.floor(Number(n));
  if (!Number.isFinite(v)) return DEFAULT_HISTORY_SIZE;
  return Math.min(HISTORY_MAX, Math.max(HISTORY_MIN, v));
}

export function isHistoryPreset(n: number): boolean {
  return (HISTORY_PRESETS as readonly number[]).includes(n);
}

class MachineStore {
  historySize = $state<number>(DEFAULT_HISTORY_SIZE);

  constructor() {
    this.historySize = clampHistory(loadJSON<number>(STORAGE_KEY, DEFAULT_HISTORY_SIZE)); // prettier-ignore

    let first = true;
    $effect.root(() => {
      $effect(() => {
        const n = this.historySize;
        saveJSON(STORAGE_KEY, n);
        if (first) {
          first = false;
          return;
        }
        sendToHaskell("set_history_size", n);
      });
    });
  }

  public sync() {
    sendToHaskell("set_history_size", this.historySize);
  }

  public reset() {
    this.historySize = DEFAULT_HISTORY_SIZE;
  }
}

export const machineStore = new MachineStore();
