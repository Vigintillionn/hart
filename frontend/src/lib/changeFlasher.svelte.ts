import { untrack } from "svelte";

export function createChangeFlasher<K = number, V = unknown>(
  getCollection: () => V[] | Map<K, V>,
  durationMs = 680,
) {
  let changed = $state(new Set<K | number>());
  let timer: number;
  let prev: Map<K | number, V> | undefined;

  $effect(() => {
    const rawCur = getCollection();

    untrack(() => {
      const curMap = new Map(rawCur.entries() as Iterable<[K | number, V]>);

      if (prev !== undefined) {
        const diff = new Set<K | number>();
        const keys = new Set([...prev.keys(), ...curMap.keys()]);

        for (const key of keys) {
          if (curMap.get(key) !== prev.get(key)) {
            diff.add(key);
          }
        }

        if (diff.size > 0) {
          changed = diff;
          clearTimeout(timer);
          timer = window.setTimeout(() => (changed = new Set()), durationMs);
        }
      }

      prev = curMap;
    });
  });

  return {
    get changed() {
      return changed;
    },
  };
}
