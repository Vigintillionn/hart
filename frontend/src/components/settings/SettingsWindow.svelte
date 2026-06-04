<script lang="ts">
  import { settingsStore } from "$lib/store/settingsStore.svelte";
  import Icon from "../Icon.svelte";
  import TextInput from "../ui/TextInput.svelte";
  import AppearancePanel from "./AppearancePanel.svelte";
  import EditorPanel from "./EditorPanel.svelte";
  import ExtensionsPanel from "./ExtensionsPanel.svelte";

  function onKeydown(e: KeyboardEvent) {
    if (settingsStore.open && e.key === "Escape") {
      e.preventDefault();
      settingsStore.close();
    }
  }

  $effect(() => {
    const visible = settingsStore.visibleCategories;
    if (
      settingsStore.q &&
      visible.length > 0 &&
      !visible.some((c) => c.id === settingsStore.active)
    ) {
      settingsStore.active = visible[0].id;
    }
  });
</script>

<svelte:window onkeydown={onKeydown} />

{#if settingsStore.open}
  <div class="fixed inset-0 z-100 flex items-center justify-center">
    <button
      class="absolute inset-0 cursor-default bg-black/50"
      aria-label="Close settings"
      onclick={() => settingsStore.close()}
    ></button>

    <div
      class="relative flex h-[78vh] max-h-160 w-190 max-w-[92vw] overflow-hidden rounded-xl border border-border-strong bg-surface-2 shadow-2xl"
      role="dialog"
      aria-modal="true"
      aria-label="Settings"
    >
      <aside
        class="flex w-56 flex-none flex-col border-r border-border bg-surface-1"
      >
        <div class="border-b border-border p-3">
          <TextInput
            icon="search"
            type="search"
            placeholder="Search settings"
            bind:value={settingsStore.query}
            autofocus
          />
        </div>
        <nav class="scroll flex-1 overflow-y-auto p-2">
          {#each settingsStore.visibleCategories as cat (cat.id)}
            <button
              onclick={() => settingsStore.select(cat.id)}
              class={[
                "flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-left text-[12.5px] transition-colors",
                settingsStore.active === cat.id
                  ? "bg-control text-text"
                  : "text-text-dim hover:bg-control/60 hover:text-text",
              ]}
            >
              <Icon
                name={cat.icon}
                class="h-4 w-4 flex-none {settingsStore.active === cat.id
                  ? 'text-primary'
                  : 'text-text-faint'}"
              />
              {cat.label}
            </button>
          {:else}
            <p class="px-2.5 py-2 text-[11.5px] text-text-faint">
              No settings found.
            </p>
          {/each}
        </nav>
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <header
          class="flex flex-none items-center justify-between border-b border-border px-5 py-3"
        >
          <h2
            class="flex items-center gap-2 text-[13px] font-semibold text-text"
          >
            <Icon name="sliders" class="h-4 w-4 text-text-faint" />
            Settings
          </h2>
          <button
            class="grid h-7 w-7 place-items-center rounded-md text-text-faint transition-colors hover:bg-surface-3 hover:text-text"
            aria-label="Close"
            onclick={() => settingsStore.close()}
          >
            <Icon name="close" class="h-4 w-4" />
          </button>
        </header>

        <div class="scroll min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {#if settingsStore.active === "appearance"}
            <AppearancePanel />
          {:else if settingsStore.active === "editor"}
            <EditorPanel />
          {:else if settingsStore.active === "extensions"}
            <ExtensionsPanel />
          {/if}
        </div>
      </div>
    </div>
  </div>
{/if}
