<script lang="ts">
  import {
    machineStore,
    HISTORY_PRESETS,
    HISTORY_MIN,
    HISTORY_MAX,
    HISTORY_DISCLAIMER,
    clampHistory,
    isHistoryPreset,
  } from "$lib/store/machineStore.svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import SegmentedControl from "../ui/SegmentedControl.svelte";
  import Icon from "../Icon.svelte";
  import SettingRow from "./SettingRow.svelte";
  import SettingsSection from "./SettingsSection.svelte";

  type Segment = number | "custom";

  const fmt = (n: number) => (n % 1000 === 0 ? `${n / 1000}K` : String(n));

  let custom = $state(!isHistoryPreset(machineStore.historySize));
  let draft = $state(String(machineStore.historySize));

  const options: { value: Segment; label: string }[] = [
    ...HISTORY_PRESETS.map((n) => ({ value: n as Segment, label: fmt(n) })),
    { value: "custom" as Segment, label: "Custom" },
  ];

  const selected = $derived<Segment>(
    custom ? "custom" : machineStore.historySize,
  );

  const draftNum = $derived.by(() => {
    const n = parseInt(draft, 10);
    return Number.isFinite(n) ? n : null;
  });

  const effective = $derived(
    custom ? (draftNum ?? machineStore.historySize) : machineStore.historySize,
  );

  function choose(v: Segment) {
    if (v === "custom") {
      custom = true;
      draft = String(machineStore.historySize);
    } else {
      custom = false;
      machineStore.historySize = v;
    }
  }

  function commit() {
    const clamped = clampHistory(draftNum ?? machineStore.historySize);
    draft = String(clamped);
    machineStore.historySize = clamped;
  }

  function onInput(e: Event) {
    draft = (e.target as HTMLInputElement).value.replace(/[^0-9]/g, "");
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === "Enter") {
      commit();
      (e.target as HTMLInputElement).blur();
    }
  }

  const showDetails = $derived(settingsStore.matchesId("machine.historySize"));
</script>

<SettingsSection title="History">
  <SettingRow id="machine.historySize">
    <SegmentedControl value={selected} onchange={choose} {options} />
  </SettingRow>

  {#if showDetails && custom}
    <div class="mt-3 flex items-center justify-end gap-1.5">
      <input
        type="text"
        inputmode="numeric"
        value={draft}
        oninput={onInput}
        onblur={commit}
        onkeydown={onKeydown}
        aria-label="Custom history size"
        class="w-28 rounded-md border border-border bg-surface-0 px-2.5 py-1.5 text-right font-mono text-[12.5px] text-text outline-none transition-colors placeholder:text-text-faint focus:border-primary/50"
      />
      <span class="text-[11.5px] text-text-faint">states</span>
    </div>
  {/if}

  {#if showDetails && custom && (draftNum === null || draftNum < HISTORY_MIN || draftNum > HISTORY_MAX)}
    <p class="mt-2 text-[11px] leading-snug text-text-faint">
      Allowed range: {HISTORY_MIN.toLocaleString()} - {HISTORY_MAX.toLocaleString()}
      states.
    </p>
  {/if}

  {#if showDetails && effective > HISTORY_DISCLAIMER}
    <div
      class="mt-2 flex items-start gap-2 rounded-md border border-amber/25 bg-amber/10 px-3 py-2 text-[11.5px] leading-snug text-amber"
    >
      <Icon name="info" class="mt-0.5 h-3.5 w-3.5 flex-none" />
      <span>
        Keeping more than {HISTORY_DISCLAIMER.toLocaleString()} states lets you rewind
        further, but the emulator will use noticeably more memory for long runs.
      </span>
    </div>
  {/if}
</SettingsSection>
