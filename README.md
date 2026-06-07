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
  extension, with the common pseudo-instructions (`li`, `la`, `ret`, ...) and
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
| **Windows** | `.exe` (NSIS installer)     |

The emulator is bundled inside the app, there's nothing else to install.

#### ⚠️ Note on Running the App (Code Signing)

Because this project is open-source and currently not code-signed with paid developer certificates, your operating system will flag it as an unrecognized app. The app is completely safe, but you will need to bypass the default security warnings:

- **Windows:** Microsoft Defender SmartScreen will show a blue warning popup. Click **More info**, then click **Run anyway**.
- **macOS:** macOS will likely say the app is "damaged and can't be opened." This is Apple's default warning for unsigned apps downloaded from the internet. To fix this, you need to remove the quarantine flag:
  1. Drag `HART.app` into your **Applications** folder.
  2. Open the **Terminal** app.
  3. Paste the following command and press Enter:
     `xattr -cr /Applications/HART.app`
  4. You can now open the app normally from your Launchpad or Applications folder.

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
┌──────────────────┐   JSON / stdio    ┌──────────────────┐   events    ┌──────────────┐
│ Haskell emulator │ ───────────────▶ │  Rust/Tauri core │ ─────────▶ │  Svelte UI   │
│  (hart-emulator) │ ◀─────────────── │   (supervisor)   │ ◀───────── │   (Monaco)   │
└──────────────────┘    commands       └──────────────────┘  commands   └──────────────┘
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
- [ ] assemble/link multiple files
- [ ] more directives (`.eqv` / `.include`)
- [ ] more syscalls
- [ ] custom traphandlers

---

## AI Usage

While I'm not a fan of pure vibecoding, AI tools have become a practical necessity in modern development, and I want to be fully transparent about how I used them across this project.

- **The Emulator**: The core emulator is 100% hand written. However I regularly use AI to audit the codebase to catch logic flaws, bugs, unidiomatic code and mismatches with the RISC-V spec.
- **The UI**: The initial design was prototyped by Claude Design, though the look and feel has drifted since then. The original Svelte implementation was generated by Claude Opus, but I have since refactored and cleaned it up into idiomatic, component-based Svelte myself.

---

## Contributing

**Status: Strictly filtered / ask first**

This project is in its early stages. To maintain momentum and ensure the core architecture heads in the right direction, I am curently the primary developer and dictate the project's roadmap. I will gladly accept all feedback and any incoming issues. I do occasionally accept PRs, provided they are well-crafted and allign with the project's goals. However, **please do not open a PR without first opening an issue to discuss it.** Drive-by PRs or unapproved feature implementations will likely be closed. See [CONTRIBUTING](CONTRIBUTING.md) for full details on my AI policy and code standards.

---

## License

[GPL-3.0](LICENSE) © 2025-2026 Vigintillionn
