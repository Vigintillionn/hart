<script lang="ts">
  import { onDestroy } from "svelte";
  import { keymap, COMMANDS, isGlyph, ARROW_PATHS } from "$lib/keymap.svelte";
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import SettingsSection from "./SettingsSection.svelte";

  const commands = $derived(
    COMMANDS.filter(
      (c) =>
        !settingsStore.q || c.label.toLowerCase().includes(settingsStore.q),
    ),
  );

  function onCaptureKeydown(e: KeyboardEvent) {
    if (!keymap.capturing) return;
    if (keymap.captureKeydown(e)) {
      e.preventDefault();
      e.stopPropagation();
    }
  }

  function onToggle(id: string) {
    if (keymap.capturing === id) keymap.cancelCapture();
    else keymap.startCapture(id);
  }

  onDestroy(() => keymap.cancelCapture());
</script>

<svelte:window onkeydowncapture={onCaptureKeydown} />

<SettingsSection title="Keyboard shortcuts">
  {#each commands as cmd (cmd.id)}
    {@const recording = keymap.capturing === cmd.id}
    {@const overridden = cmd.id in keymap.overrides}
    <div
      class="flex items-center justify-between gap-6 border-b border-border-soft py-3 last:border-0"
    >
      <div class="min-w-0 text-[13px] font-medium text-text">{cmd.label}</div>
      <div class="flex flex-none items-center gap-2">
        {#if overridden && !recording}
          <button
            class="text-[11px] text-text-faint cursor-pointer transition-colors hover:text-text hover:underline"
            title="Reset to default"
            onclick={() => keymap.resetBinding(cmd.id)}>Reset</button
          >
        {/if}
        <button
          onclick={() => onToggle(cmd.id)}
          aria-label={`Change shortcut for ${cmd.label}`}
          class={[
            "flex min-w-28 items-center cursor-pointer justify-center gap-1 rounded-md px-2 py-1.5 transition-colors",
            recording
              ? "bg-primary-line ring-1 ring-primary"
              : "hover:bg-surface-3",
          ]}
        >
          {#if recording}
            <span
              class="animate-pulse h-6 flex items-center justify-center font-mono text-[11px] text-primary"
            >
              Press keys…
            </span>
          {:else}
            {#each keymap.partsFor(cmd.id) as key (key)}
              <kbd
                class={[
                  "grid h-6 min-w-6 place-items-center rounded-[5px] border border-border-strong bg-surface-2 px-1.5 font-mono text-text shadow-[0_1.5px_0_0_rgba(0,0,0,0.35)]",
                  isGlyph(key) ? "text-[14px] leading-none" : "text-[11px]",
                ]}
              >
                {#if ARROW_PATHS[key]}
                  <svg
                    class="h-3.5 w-3.5"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path d={ARROW_PATHS[key]} />
                  </svg>
                {:else}
                  {key}
                {/if}
              </kbd>
            {/each}
          {/if}
        </button>
      </div>
    </div>
  {:else}
    <p class="py-2 text-[11.5px] text-text-faint">No shortcuts found.</p>
  {/each}

  {#if !settingsStore.q}
    <p class="mt-3 text-[11px] leading-snug text-text-faint">
      Click a shortcut, then press the new key combination. Press
      <span class="font-mono">Esc</span> to cancel.
    </p>
  {/if}
</SettingsSection>
