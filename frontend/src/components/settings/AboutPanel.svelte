<script lang="ts">
  import { onMount } from "svelte";
  import { open } from "@tauri-apps/plugin-shell";
  import { getVersion } from "@tauri-apps/api/app";
  import { logStore } from "$lib/store/logStore.svelte";
  import Logo from "../Logo.svelte";
  import Icon from "../Icon.svelte";
  import SettingsSection from "./SettingsSection.svelte";

  const REPO_URL = "https://github.com/Vigintillionn/hart";
  const LICENSE_URL = `${REPO_URL}/blob/main/LICENSE`;
  const AUTHOR_URL = "https://yarne.me";

  const linkClass =
    "align-baseline text-primary underline-offset-2 transition-colors hover:underline";

  let version = $state("");

  onMount(async () => {
    try {
      version = await getVersion();
    } catch {}
  });

  async function openExternal(url: string) {
    try {
      await open(url);
    } catch (e) {
      logStore.log("error", "ABOUT", `Couldn't open ${url}: ${String(e)}`);
    }
  }

  function reportIssue() {
    const environment = `HART ${version || "(unknown version)"} · ${navigator.userAgent}`;
    const url =
      `${REPO_URL}/issues/new?template=bug_report.yml` +
      `&environment=${encodeURIComponent(environment)}`;
    void openExternal(url);
  }
</script>

<SettingsSection title="About">
  <div class="flex items-center justify-between gap-3">
    <Logo />
    <span class="text-[12px] tabular-nums text-text-faint">
      {version ? `v${version}` : ""}
    </span>
  </div>
  <p class="mt-3 text-[12px] leading-relaxed text-text-dim">
    A desktop IDE and time-travel debugger for RISC-V assembly.
  </p>
  <p class="mt-3 text-[12px] text-text-dim">
    Released under the <button
      onclick={() => openExternal(LICENSE_URL)}
      class={linkClass}>GPL-3.0</button
    > license.
  </p>
  <p class="mt-1 text-[12px] text-text-dim">
    Made with <span class="text-red" aria-hidden="true">♥</span> by
    <button onclick={() => openExternal(AUTHOR_URL)} class={linkClass}
      >Yarne</button
    >.
  </p>
</SettingsSection>

<SettingsSection title="Feedback">
  <p class="mb-3 text-[12px] leading-relaxed text-text-dim">
    Hit a bug, a crash, or something that behaves unexpectedly? Opening a report
    takes you to GitHub with a short form — your app version and platform are
    filled in for you.
  </p>
  <div class="flex flex-wrap items-center gap-2">
    <button
      onclick={reportIssue}
      class="flex items-center gap-2 rounded-md bg-control px-3 py-1.5 text-[12.5px] font-medium text-text transition-colors hover:bg-control/70"
    >
      <Icon name="bug" class="h-4 w-4 text-primary" />
      Report an issue
    </button>
    <button
      onclick={() => openExternal(REPO_URL)}
      class="rounded-md px-3 py-1.5 text-[12.5px] text-text-dim transition-colors hover:bg-control/60 hover:text-text"
    >
      View on GitHub
    </button>
  </div>
</SettingsSection>
