import { invoke } from "@tauri-apps/api/core";

const CANONICAL_NAMES: string[] = [
  "zero",
  "ra",
  "sp",
  "gp",
  "tp",
  "t0",
  "t1",
  "t2",
  "s0",
  "s1",
  "a0",
  "a1",
  "a2",
  "a3",
  "a4",
  "a5",
  "a6",
  "a7",
  "s2",
  "s3",
  "s4",
  "s5",
  "s6",
  "s7",
  "s8",
  "s9",
  "s10",
  "s11",
  "t3",
  "t4",
  "t5",
  "t6",
];

export async function sendToHaskell(command: string, data?: string) {
  const payload = data ? { command, data } : { command };
  await invoke("send_command", { cmd: JSON.stringify(payload) });
}

export function toHex(num: number) {
  return "0x" + (num >>> 0).toString(16).padStart(8, "0");
}

export function getRegName(index: number, showCanonicalNames: boolean) {
  if (!showCanonicalNames) return `x${index}`;
  return CANONICAL_NAMES[index] || `x${index}`;
}
