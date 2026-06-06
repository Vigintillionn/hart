<script lang="ts">
  let value = $state(0);
  let active = $state<string | null>(null);
  let raw = $state("");

  const toU32 = (n: number) => n >>> 0;

  const printable = (b: number) =>
    b >= 32 && b < 127 ? String.fromCharCode(b) : "·";

  function bytes(v: number): number[] {
    return [(v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff];
  }

  type Field = {
    key: string;
    label: string;
    hint: string;
    mono?: boolean;
    format: (v: number) => string;
    parse: (s: string) => number | null;
  };

  const fields: Field[] = [
    {
      key: "udec",
      label: "Unsigned",
      hint: "0 … 4294967295",
      format: (v) => String(v),
      parse: (s) => (/^\d+$/.test(s.trim()) ? toU32(Number(s.trim())) : null),
    },
    {
      key: "sdec",
      label: "Signed",
      hint: "two's complement, -2147483648 … 2147483647",
      format: (v) => String(v | 0),
      parse: (s) =>
        /^-?\d+$/.test(s.trim()) ? toU32(Number(s.trim()) & 0xffffffff) : null,
    },
    {
      key: "hex",
      label: "Hex",
      hint: "base 16",
      mono: true,
      format: (v) => "0x" + v.toString(16).padStart(8, "0").toUpperCase(),
      parse: (s) => {
        const t = s.trim().replace(/^0x/i, "");
        return /^[0-9a-f]+$/i.test(t) ? toU32(parseInt(t, 16)) : null;
      },
    },
    {
      key: "bin",
      label: "Binary",
      hint: "base 2",
      mono: true,
      format: (v) =>
        v
          .toString(2)
          .padStart(32, "0")
          .replace(/(.{4})(?=.)/g, "$1 "),
      parse: (s) => {
        const t = s.replace(/\s+/g, "");
        return /^[01]+$/.test(t) ? toU32(parseInt(t, 2)) : null;
      },
    },
    {
      key: "ascii",
      label: "ASCII",
      hint: "4 bytes, big-endian; non-printable shown as ·",
      mono: true,
      format: (v) => bytes(v).map(printable).join(" "),
      parse: (s) => {
        // last character is the least-significant byte
        const cs = [...s].slice(-4);
        let v = 0;
        for (const c of cs) v = ((v << 8) | (c.charCodeAt(0) & 0xff)) >>> 0;
        return v;
      },
    },
  ];

  function display(f: Field): string {
    return active === f.key ? raw : f.format(value);
  }

  function isInvalid(f: Field): boolean {
    return active === f.key && raw !== "" && f.parse(raw) === null;
  }

  function onFocus(f: Field) {
    active = f.key;
    raw = f.format(value);
  }
  function onInput(f: Field, e: Event) {
    raw = (e.target as HTMLInputElement).value;
    const parsed = f.parse(raw);
    if (parsed !== null) value = parsed;
  }
  function onBlur() {
    active = null;
  }
</script>

<section class="mb-7 max-w-md last:mb-0">
  <div class="mb-1 flex items-center gap-2">
    <h3 class="text-[12.5px] font-semibold text-text">Number converter</h3>
  </div>
  <p class="mb-4 text-[11px] leading-snug text-text-dim">
    Convert a 32-bit value between bases.
  </p>

  <div class="flex flex-col gap-2.5">
    {#each fields as f (f.key)}
      <label class="flex flex-col gap-1">
        <span
          class="flex items-baseline justify-between text-[10px] uppercase tracking-[1px] text-text-faint"
        >
          {f.label}
          <span class="tracking-normal normal-case text-text-ghost">
            {f.hint}
          </span>
        </span>
        <input
          spellcheck="false"
          autocomplete="off"
          value={display(f)}
          oninput={(e) => onInput(f, e)}
          onfocus={() => onFocus(f)}
          onblur={onBlur}
          class={[
            "w-full rounded-md border bg-surface-0 px-2.5 py-1.5 text-[12px] text-text outline-none transition",
            "font-mono",
            isInvalid(f)
              ? "border-red focus:border-red"
              : "border-border focus:border-primary-soft focus:shadow-[0_0_0_3px_var(--color-primary-line)]",
          ]}
        />
      </label>
    {/each}
  </div>
</section>
