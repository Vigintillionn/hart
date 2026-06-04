<script lang="ts">
  let {
    checked = $bindable(false),
    disabled = false,
    label,
    onchange,
  }: {
    checked?: boolean;
    disabled?: boolean;
    label?: string;
    onchange?: (value: boolean) => void;
  } = $props();

  function toggle() {
    if (disabled) return;
    checked = !checked;
    onchange?.(checked);
  }
</script>

<button
  type="button"
  role="switch"
  aria-checked={checked}
  aria-label={label}
  {disabled}
  onclick={toggle}
  class={[
    "relative h-5 w-9 flex-none rounded-full transition-colors",
    checked ? "bg-primary-soft" : "bg-border-strong",
    disabled
      ? "cursor-not-allowed opacity-50"
      : "cursor-pointer hover:brightness-110",
  ]}
>
  <span
    class={[
      "absolute left-0.5 top-0.5 h-4 w-4 rounded-full shadow-sm transition-transform duration-150",
      checked ? "translate-x-4 bg-primary" : "translate-x-0 bg-text-faint",
    ]}
  ></span>
</button>
