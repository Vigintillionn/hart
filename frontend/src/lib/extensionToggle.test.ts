import { describe, expect, it } from "vitest";
import { toggleExtension } from "./extensionToggle";
import type { ExtensionInfo } from "../bindings/ExtensionInfo";

function ext(
  code: string,
  enabled: boolean,
  requires: string[] = [],
  mandatory = false,
): ExtensionInfo {
  return { code, name: code, summary: "", mandatory, requires, enabled };
}

function enabledCodes(catalogue: ExtensionInfo[]): string[] {
  return catalogue.filter((e) => e.enabled).map((e) => e.code);
}

describe("toggleExtension", () => {
  it("enables an extension together with what it requires, transitively", () => {
    const catalogue = [
      ext("I", true, [], true),
      ext("Zicsr", false),
      ext("F", false, ["Zicsr"]),
      ext("D", false, ["F"]),
    ];
    expect(enabledCodes(toggleExtension(catalogue, "D"))).toEqual([
      "I",
      "Zicsr",
      "F",
      "D",
    ]);
  });

  it("disables an extension together with whatever requires it", () => {
    const catalogue = [
      ext("I", true, [], true),
      ext("M", true),
      ext("Zicsr", true),
      ext("F", true, ["Zicsr"]),
      ext("D", true, ["F"]),
    ];
    expect(enabledCodes(toggleExtension(catalogue, "Zicsr"))).toEqual([
      "I",
      "M",
    ]);
  });

  it("leaves requirements on when a dependent is disabled", () => {
    const catalogue = [ext("Zicsr", true), ext("F", true, ["Zicsr"])];
    expect(enabledCodes(toggleExtension(catalogue, "F"))).toEqual(["Zicsr"]);
  });

  it("ignores mandatory and unknown extensions", () => {
    const catalogue = [ext("I", true, [], true), ext("M", false)];
    expect(toggleExtension(catalogue, "I")).toBe(catalogue);
    expect(toggleExtension(catalogue, "X")).toBe(catalogue);
  });
});
