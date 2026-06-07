import { getContext, setContext } from "svelte";

export interface SectionRegistry {
  report(id: string, visible: boolean): void;
}

const SECTION_KEY = Symbol("settings-section");

export function provideSection(registry: SectionRegistry): void {
  setContext(SECTION_KEY, registry);
}

export function useSection(): SectionRegistry | undefined {
  return getContext(SECTION_KEY);
}
