<script lang="ts">
  import type { IconName } from "$lib/types";

  let { name, class: cls = "w-4 h-4" }: { name: IconName; class?: string } =
    $props();
</script>

<svg
  class={cls}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="1.7"
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>
  {#if name === "play"}
    <path
      d="M8 5.2v13.6a.6.6 0 0 0 .92.5l10.6-6.8a.6.6 0 0 0 0-1L8.92 4.7A.6.6 0 0 0 8 5.2Z"
      fill="currentColor"
      stroke="none"
    />
  {:else if name === "pause"}
    <rect
      x="7"
      y="5"
      width="3.5"
      height="14"
      rx="1"
      fill="currentColor"
      stroke="none"
    />
    <rect
      x="13.5"
      y="5"
      width="3.5"
      height="14"
      rx="1"
      fill="currentColor"
      stroke="none"
    />
  {:else if name === "stepFwd"}
    <path
      d="M5 5.5v13a.4.4 0 0 0 .62.34l9.2-6.5a.4.4 0 0 0 0-.68l-9.2-6.5A.4.4 0 0 0 5 5.5Z"
      fill="currentColor"
      stroke="none"
    />
    <path d="M19 5v14" />
  {:else if name === "stepBack"}
    <path
      d="M19 5.5v13a.4.4 0 0 1-.62.34l-9.2-6.5a.4.4 0 0 1 0-.68l9.2-6.5A.4.4 0 0 1 19 5.5Z"
      fill="currentColor"
      stroke="none"
    />
    <path d="M5 5v14" />
  {:else if name === "rewind"}
    <path
      d="M21 6v12a.35.35 0 0 1-.55.29l-7.9-5.7a.35.35 0 0 1 0-.58l7.9-5.7A.35.35 0 0 1 21 6Z"
      fill="currentColor"
      stroke="none"
    />
    <path
      d="M11 6v12a.35.35 0 0 1-.55.29l-7.9-5.7a.35.35 0 0 1 0-.58l7.9-5.7A.35.35 0 0 1 11 6Z"
      fill="currentColor"
      stroke="none"
    />
  {:else if name === "search"}
    <circle cx="11" cy="11" r="7" />
    <path d="m20 20-3.2-3.2" />
  {:else if name === "trash"}
    <path
      d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2m2 0-.7 12a2 2 0 0 1-2 1.9H8.7a2 2 0 0 1-2-1.9L6 7"
    />
  {:else if name === "term"}
    <path d="m5 8 4 4-4 4M12 16h7" />
  {:else if name === "logs"}
    <path d="M5 7h14M5 12h14M5 17h9" />
  {:else if name === "lock"}
    <rect x="5" y="11" width="14" height="9" rx="2" />
    <path d="M8 11V8a4 4 0 0 1 8 0v3" />
  {:else if name === "pencil"}
    <path d="M4 20h4L19 9a2.1 2.1 0 0 0-3-3L5 17v3Z" />
    <path d="M14 6.5 17.5 10" />
  {:else if name === "build"}
    <path d="M3 12h3l2 5 4-12 2 7h2.5M18.5 12H21" />
  {:else if name === "folder"}
    <path
      d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"
    />
  {:else if name === "save"}
    <path d="M5 4h11l3 3v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1Z" />
    <path d="M8 4v5h7M8 21v-6h8v6" />
  {:else if name === "sliders"}
    <path d="M4 8h10M18 8h2M4 16h2M10 16h10" />
    <circle cx="16" cy="8" r="2.2" fill="currentColor" stroke="none" />
    <circle cx="8" cy="16" r="2.2" fill="currentColor" stroke="none" />
  {:else if name === "panels"}
    <rect x="3.5" y="4.5" width="17" height="15" rx="2" />
    <path d="M14 4.5v15" />
  {:else if name === "chip"}
    <rect x="7" y="7" width="10" height="10" rx="1.5" />
    <path
      d="M10 2.5v2.5M14 2.5v2.5M10 19v2.5M14 19v2.5M2.5 10H5M2.5 14H5M19 10h2.5M19 14h2.5"
    />
  {:else if name === "cpu"}
    <rect x="5" y="5" width="14" height="14" rx="2" />
    <rect x="9" y="9" width="6" height="6" rx="1" />
    <path
      d="M8 2.5v2.5M12 2.5v2.5M16 2.5v2.5M8 19v2.5M12 19v2.5M16 19v2.5M2.5 8H5M2.5 12H5M2.5 16H5M19 8h2.5M19 12h2.5M19 16h2.5"
    />
  {:else if name === "sun"}
    <circle cx="12" cy="12" r="4" />
    <path
      d="M12 2v2.5M12 19.5V22M4.22 4.22l1.77 1.77M18.01 18.01l1.77 1.77M2 12h2.5M19.5 12H22M4.22 19.78l1.77-1.77M18.01 5.99l1.77-1.77"
    />
  {:else if name === "moon"}
    <path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5Z" />
  {:else if name === "keyboard"}
    <rect x="2.5" y="6" width="19" height="12" rx="2" />
    <path
      d="M6 9.5h.01M9.5 9.5h.01M13 9.5h.01M16.5 9.5h.01M6 13h.01M16.5 13h.01M9 13h6"
    />
  {:else if name === "memory"}
    <rect x="6" y="6" width="12" height="12" rx="1.5" />
    <path
      d="M9 2.5v3M15 2.5v3M9 18.5v3M15 18.5v3M2.5 9h3M2.5 15h3M18.5 9h3M18.5 15h3M9.5 9.5h5v5h-5z"
    />
  {:else if name === "book"}
    <path
      d="M4 5.5A1.5 1.5 0 0 1 5.5 4H11a2 2 0 0 1 2 2v13a1.6 1.6 0 0 0-1.6-1.6H5.5A1.5 1.5 0 0 1 4 16Z"
    />
    <path
      d="M20 5.5A1.5 1.5 0 0 0 18.5 4H13a2 2 0 0 0-2 2v13a1.6 1.6 0 0 1 1.6-1.6h5.9A1.5 1.5 0 0 0 20 16Z"
    />
  {:else if name === "chevron"}
    <path d="m6 9 6 6 6-6" />
  {:else if name === "check"}
    <path d="m5 12.5 4.5 4.5L19 7" />
  {:else if name === "min"}
    <path d="M5 12h14" stroke-width="1.5" />
  {:else if name === "max"}
    <rect x="5.5" y="5.5" width="13" height="13" rx="1.5" stroke-width="1.4" />
  {:else if name === "restore"}
    <rect x="7.5" y="7.5" width="11" height="11" rx="1.4" stroke-width="1.4" />
    <path d="M7.5 5.5h9a2 2 0 0 1 2 2v9" stroke-width="1.4" />
  {:else if name === "close"}
    <path d="M6 6l12 12M18 6 6 18" stroke-width="1.5" />
  {:else if name === "info"}
    <circle cx="12" cy="12" r="9" />
    <path d="M12 11v5" />
    <path d="M12 8h.01" />
  {:else if name === "bug"}
    <path d="M9 8V7a3 3 0 0 1 6 0v1" />
    <path d="M9.5 5 8 3.5M14.5 5 16 3.5" />
    <rect x="8" y="8" width="8" height="10.5" rx="4" />
    <path d="M12 11.5v6.5" />
    <path d="M8 10.5 4.5 8.5M16 10.5l3.5-2" />
    <path d="M8 14H4M16 14h4" />
    <path d="M8 16.5 5 18.5M16 16.5l3 2" />
  {/if}
</svg>
