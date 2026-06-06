import { invoke } from "@tauri-apps/api/core";
import { logStore } from "./store/logStore.svelte";

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

// Memory layout of the Haskell emulator (see emulator/lib/Machine.hs & Linker.hs)
export const TEXT_BASE = 0x0;
export const DATA_BASE = 0x10000000;
export const HEAP_BASE = 0x20000000;
export const STACK_TOP = 0x7fffffff;

export async function sendToHaskell(
  command: string,
  data?: string | number[] | string[],
) {
  const payload = data !== undefined ? { command, data } : { command };
  try {
    await invoke("send_command", { cmd: JSON.stringify(payload) });
  } catch (e) {
    logStore.log("error", "IPC", `failed to send "${command}": ${e}`);
  }
}

/** @returns 8-digit hex word, e.g. 0x0001002a */
export function toHex(num: number) {
  return "0x" + hex32(num);
}

/** @returns bare 8-digit hex (no 0x prefix) */
export function hex32(num: number) {
  return (num >>> 0).toString(16).padStart(8, "0");
}

/** @returns 2-digit hex byte */
export function hex2(num: number) {
  return (num & 0xff).toString(16).padStart(2, "0");
}

/** @returns the ABI name for a register index, or its bare hex (e.g. `x15`) */
export function getRegName(index: number, showCanonicalNames: boolean) {
  if (!showCanonicalNames) return `x${index}`;
  return CANONICAL_NAMES[index] || `x${index}`;
}

// Control & Status Registers known to the Haskell emulator
// (see emulator/lib/Types.hs `csrInfo`). addr → [name, description]
const CSR_INFO: Record<number, [string, string]> = {
  0x300: ["mstatus", "Machine status"],
  0x301: ["misa", "ISA & extensions"],
  0x304: ["mie", "Machine interrupt-enable"],
  0x305: ["mtvec", "Trap-handler base address"],
  0x340: ["mscratch", "Scratch register for trap handlers"],
  0x341: ["mepc", "Machine exception program counter"],
  0x342: ["mcause", "Trap cause"],
  0x343: ["mtval", "Bad address / instruction"],
  0x344: ["mip", "Machine interrupt-pending"],
};

/** @returns the ABI name for a CSR address, or its bare hex (e.g. `0x7c0`) */
export function getCsrName(addr: number): string {
  return CSR_INFO[addr]?.[0] ?? "0x" + (addr >>> 0).toString(16);
}

/** @returns a human description for a CSR address, or "" if unknown */
export function getCsrDescription(addr: number): string {
  return CSR_INFO[addr]?.[1] ?? "";
}

/** @returns 3-digit hex CSR address, e.g. 0x305 */
export function hex12(addr: number): string {
  return "0x" + (addr >>> 0).toString(16).padStart(3, "0");
}

/** @returns a formatted string for a register value, either in hex or decimal */
export function fmtRegisterValue(
  v: number,
  hexMode: boolean,
  signedMode: boolean,
) {
  if (hexMode) return hex32(v);
  return signedMode ? (v | 0).toString() : (v >>> 0).toString();
}

/** @returns 32-bit binary grouped in bytes, e.g. `00000000 11111100 ...` */
export function bin32(num: number) {
  const bits = (num >>> 0).toString(2).padStart(32, "0");
  return bits.replace(/(.{8})(?=.)/g, "$1 ");
}

/** @returns an assembled instruction word as hex (`0x…`) or grouped binary */
export function fmtInstrCode(word: number, hexMode: boolean) {
  return hexMode ? toHex(word) : bin32(word);
}
