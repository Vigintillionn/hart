import { describe, expect, it, vi } from "vitest";

vi.mock("./store/logStore.svelte", () => ({ logStore: { log: () => {} } }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: async () => {} }));

import {
  bin32,
  fmtInstrCode,
  fmtRegisterValue,
  getCsrDescription,
  getCsrName,
  getRegName,
  hex2,
  hex12,
  hex32,
  toHex,
} from "./util";

describe("hex formatting", () => {
  it("toHex / hex32 pad to 8 digits", () => {
    expect(toHex(0x1002a)).toBe("0x0001002a");
    expect(hex32(0)).toBe("00000000");
    expect(hex32(0xdeadbeef)).toBe("deadbeef");
  });

  it("treats values as unsigned 32-bit", () => {
    expect(hex32(-1)).toBe("ffffffff");
    expect(toHex(-1)).toBe("0xffffffff");
  });

  it("hex2 masks to a single byte", () => {
    expect(hex2(0)).toBe("00");
    expect(hex2(0x1ff)).toBe("ff");
    expect(hex2(5)).toBe("05");
  });

  it("hex12 pads CSR addresses to 3 digits", () => {
    expect(hex12(0x305)).toBe("0x305");
    expect(hex12(0x7)).toBe("0x007");
  });
});

describe("getRegName", () => {
  it("returns ABI names when canonical names are requested", () => {
    expect(getRegName(0, true)).toBe("zero");
    expect(getRegName(2, true)).toBe("sp");
    expect(getRegName(17, true)).toBe("a7");
    expect(getRegName(31, true)).toBe("t6");
  });

  it("returns x-names when canonical names are off", () => {
    expect(getRegName(0, false)).toBe("x0");
    expect(getRegName(15, false)).toBe("x15");
  });

  it("falls back to x-name for an out-of-range index", () => {
    expect(getRegName(99, true)).toBe("x99");
  });
});

describe("CSR metadata", () => {
  it("resolves known CSR names and descriptions", () => {
    expect(getCsrName(0x341)).toBe("mepc");
    expect(getCsrDescription(0x342)).toBe("Trap cause");
  });

  it("falls back to hex for unknown CSRs and empty description", () => {
    expect(getCsrName(0x7c0)).toBe("0x7c0");
    expect(getCsrDescription(0x7c0)).toBe("");
  });
});

describe("value formatting", () => {
  it("fmtRegisterValue switches between hex and signed decimal", () => {
    expect(fmtRegisterValue(0xffffffff, true, false)).toBe("ffffffff");
    expect(fmtRegisterValue(0xffffffff, false, true)).toBe("-1");
    expect(fmtRegisterValue(42, false, false)).toBe("42");
  });

  it("bin32 groups 32 bits into bytes", () => {
    expect(bin32(0)).toBe("00000000 00000000 00000000 00000000");
    expect(bin32(0xff)).toBe("00000000 00000000 00000000 11111111");
  });

  it("fmtInstrCode renders hex or grouped binary", () => {
    expect(fmtInstrCode(0x13, true)).toBe("0x00000013");
    expect(fmtInstrCode(0x13, false)).toBe(
      "00000000 00000000 00000000 00010011",
    );
  });
});
