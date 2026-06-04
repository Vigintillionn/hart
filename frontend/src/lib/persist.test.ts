import { afterEach, describe, expect, it, vi } from "vitest";
import { loadJSON, saveJSON } from "./persist";

function fakeStorage(initial: Record<string, string> = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (k: string) => (map.has(k) ? map.get(k)! : null),
    setItem: (k: string, v: string) => void map.set(k, v),
    removeItem: (k: string) => void map.delete(k),
    clear: () => map.clear(),
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("loadJSON", () => {
  it("returns the stored value when present and valid", () => {
    vi.stubGlobal("localStorage", fakeStorage({ k: JSON.stringify({ a: 1 }) }));
    expect(loadJSON("k", { a: 0 })).toEqual({ a: 1 });
  });

  it("returns the fallback when the key is missing", () => {
    vi.stubGlobal("localStorage", fakeStorage());
    expect(loadJSON("missing", "fallback")).toBe("fallback");
  });

  it("returns the fallback when the stored value is corrupt", () => {
    vi.stubGlobal("localStorage", fakeStorage({ k: "{not json" }));
    expect(loadJSON("k", 42)).toBe(42);
  });

  it("returns the fallback when localStorage is unavailable", () => {
    vi.stubGlobal("localStorage", undefined);
    expect(loadJSON("k", "fallback")).toBe("fallback");
  });
});

describe("saveJSON", () => {
  it("round-trips a value through loadJSON", () => {
    vi.stubGlobal("localStorage", fakeStorage());
    saveJSON("k", { hello: "world" });
    expect(loadJSON("k", null)).toEqual({ hello: "world" });
  });

  it("does not throw when storage is unavailable", () => {
    vi.stubGlobal("localStorage", undefined);
    expect(() => saveJSON("k", { a: 1 })).not.toThrow();
  });

  it("does not throw when setItem fails (e.g. quota exceeded)", () => {
    vi.stubGlobal("localStorage", {
      getItem: () => null,
      setItem: () => {
        throw new Error("QuotaExceededError");
      },
    });
    expect(() => saveJSON("k", { a: 1 })).not.toThrow();
  });
});
