# HART (Haskell Assembler for RISC-V Teaching)

**A desktop IDE and time-travel debugger for RISC-V assembly.**

HART lets you write RV32IM assembly, run it, and step through it forwards _and
backwards_ while watching every register, CSR, and byte of memory change. It
pairs a Monaco-based editor with a from-scratch RISC-V emulator, so it's a
practical tool for learning and teaching how RISC-V actually works.

> The name is a nod to a RISC-V **hart** (_hardware thread_); the execution
> context that runs a stream of instructions.

---

## Features

- **RV32IM assembly**: the base integer ISA plus the M (multiply/divide)
  extension, with the common pseudo-instructions (`li`, `la`, `ret`, …) and
  directives (`.text`, `.data`, `.string`, `.word`, `.space`, `.align`).
- **Toggleable extensions**: enable/disable extensions (e.g. M) from the
  toolbar; a disabled extension won't assemble or run. The base set is always on.
- **Time-travel debugging**: step forward, step _back_, and rewind to the
  start. Every CPU state is recorded, so going backwards is instant and exact.
- **Live machine state**: the PC, all 32 registers (ABI names), CSRs, and a hex
  memory view that flashes on writes.
- **Source-mapped execution**: the current instruction is highlighted in your
  code as the CPU advances.
- **Interactive I/O**: programs that read `stdin` pause for you to type into an
  embedded terminal. Common `ecall` syscalls (print/read int & string, `sbrk`,
  file ops) are supported.

---

## Install

### Download a release

Grab the build for your platform from the [Releases][releases] page:

| Platform    | Files                       |
| ----------- | --------------------------- |
| **macOS**   | `.dmg` / `.app`             |
| **Linux**   | `.AppImage`, `.deb`, `.rpm` |
| **Windows** | `.msi`, `.exe`              |

The emulator is bundled inside the app — there's nothing else to install.

> Builds aren't code-signed yet, so the OS may warn that HART is from an
> unidentified developer. On macOS, right-click the app → **Open**; on Windows,
> choose **More info → Run anyway**.

### Build from source

You'll need [GHC ≥ 9.6 + Cabal][ghcup] (emulator),
[Rust][rust] (Tauri shell), and [Node ≥ 20 + pnpm][pnpm] (frontend).

```bash
git clone https://github.com/Vigintillionn/hart.git
cd hart/frontend

pnpm install
pnpm build-sidecar   # build the Haskell emulator into the sidecar
pnpm tauri dev       # run the app

# or package installers for your platform:
pnpm tauri build
```

[releases]: https://github.com/Vigintillionn/hart/releases
[ghcup]: https://www.haskell.org/ghcup/
[rust]: https://www.rust-lang.org/tools/install
[pnpm]: https://pnpm.io/

---

## How it works

Three small pieces talk over a line-delimited JSON protocol:

```
┌──────────────────┐   JSON / stdio   ┌──────────────────┐   events   ┌──────────────┐
│ Haskell emulator │ ───────────────▶ │  Rust/Tauri core │ ─────────▶ │  Svelte UI   │
│  (hart-emulator) │ ◀─────────────── │   (supervisor)   │ ◀───────── │   (Monaco)   │
└──────────────────┘    commands      └──────────────────┘  commands  └──────────────┘
```

- The **Haskell emulator** parses, assembles, runs, and records execution.
- The **Rust/Tauri shell** supervises it as a sidecar and bridges stdin/stdout
  to the UI.
- The **Svelte UI** is the editor, debugger, and console.

Each subproject has its own README:

| Path                              | What it is                                            |
| --------------------------------- | ----------------------------------------------------- |
| [`emulator/`](emulator/README.md) | The Haskell RV32IM assembler, emulator, and debugger. |
| [`frontend/`](frontend/README.md) | The Tauri + SvelteKit desktop app.                    |

---

## Roadmap

- [ ] more extensions (`F`, `D`, `C`)
- [ ] user-defined extensions / instructions
- [ ] UI themes and a proper settings panel
- [ ] RV64I support
- [ ] edit register/memory values from the UI while running
- [ ] LUA for custom memory mapped I/O and custom syscalls

---

## License

[GPL-3.0](LICENSE) © 2025-2026 Vigintillionn
