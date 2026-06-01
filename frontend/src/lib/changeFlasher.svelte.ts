import { untrack } from "svelte";

export function createChangeFlasher<K = number, V = unknown>(
  getCollection: () => V[] | Map<K, V>,
  durationMs = 680,
) {
  let changed = $state(new Set<K | number>());
  let timer: number;
  let prev: Map<K | number, V> | undefined;

  // This is intentionally an $effect, not a $derived: the result depends on the
  // *previous* value of the collection (to diff against) and on a timer that
  // clears the highlight after `durationMs`. That temporal, self-clearing state
  // can't be expressed as a pure derivation of the current input, we're
  // observing change-over-time and writing a transient signal, which is exactly
  // what an effect is for. `untrack` keeps the diff bookkeeping from making
  // `changed`/`prev` reads into dependencies (only `getCollection()` should be).
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
