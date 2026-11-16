import type { ExtensionInfo } from "../bindings/ExtensionInfo";

function reachable(
  start: string,
  neighbours: (code: string) => string[],
): Set<string> {
  const seen = new Set<string>();
  const pending = [start];
  while (pending.length) {
    const code = pending.pop()!;
    if (seen.has(code)) continue;
    seen.add(code);
    pending.push(...neighbours(code));
  }
  return seen;
}

/**
 * Flip one extension, keeping the set consistent: enabling also enables what
 * it requires, disabling also disables whatever requires it.
 */
export function toggleExtension(
  catalogue: ExtensionInfo[],
  code: string,
): ExtensionInfo[] {
  const target = catalogue.find((e) => e.code === code);
  if (!target || target.mandatory) return catalogue;

  const enabling = !target.enabled;
  const affected = enabling
    ? reachable(
        code,
        (c) => catalogue.find((e) => e.code === c)?.requires ?? [],
      )
    : reachable(code, (c) =>
        catalogue.filter((e) => e.requires.includes(c)).map((e) => e.code),
      );

  return catalogue.map((e) =>
    affected.has(e.code) && !e.mandatory ? { ...e, enabled: enabling } : e,
  );
}
