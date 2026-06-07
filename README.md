# HART (Haskell Assembler for RISC-V Teaching)

**A desktop IDE and time-travel debugger for RISC-V assembly.**

HART lets you write, run, and time-travel debug RV32IM assembly. It pairs a Monaco-based editor with a custom RISC-V emulator built in Haskell, providing full visibility into registers, CSRs, and memory state as instructions execute.

---

## Features

- **RV32IM assembly**: Supports the base integer ISA plus the M extension, standard pseudo-instructions, and common directives.
- **Time-travel debugging**: Step forward, backward, or rewind instantly. Every CPU state is recorded.
- **Live machine state**: View the PC, 32 registers, CSRs, and a flashing hex memory view on writes.
- **Source-mapped execution**: The current instruction is highlighted in the editor as the CPU advances.
- **Interactive I/O**: Built-in terminal for `stdin`/`stdout`. Supports common `ecall` operations (print, read, sbrk, file I/O).
- **Toggleable Extensions**: Enable or disable extensions on the fly (base set is always on).

---

## Installation

Download the latest release for your platform from the [Releases][releases] page:

| Platform    | Files                       |
| ----------- | --------------------------- |
| **macOS**   | `.dmg` / `.app`             |
| **Linux**   | `.AppImage`, `.deb`, `.rpm` |
| **Windows** | `.exe` (NSIS installer)     |

The emulator is bundled inside the app, there's nothing else to install.

**Note on unsigned binaries**: The app is currently not code-signed.

- Windows: If SmartScreen blocks the app, click **More info** -> **Run anyway**.
- macOS: If macOS flags the app as "damaged", you need to remove the quarantine flag. Move `HART.app` to your Applications folder, then run `xattr -cr /Applications/HART.app` in your terminal.

### Build from source

Requires [GHC ≥ 9.6 + Cabal][ghcup],
[Rust][rust], and [Node ≥ 20 + pnpm][pnpm].

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

## Roadmap

- [ ] Support more extensions (`F`, `D`, `C`)
- [ ] User-defined extensions and instructions
- [ ] UI themes
- [ ] RV64I support
- [ ] Live-edit register/memory values from the UI
- [ ] LUA bindings for custom memory mapped I/O
- [ ] Assembler support for multiple files
- [ ] More directives (`.eqv`, `.include`)
- [ ] More syscalls
- [ ] Custom traphandlers

---

## Development notes

Development Notes

- **AI Transparency**: The core emulator is hand-written, with LLMs used occasionally to audit against the RISC-V spec. The frontend was initially scaffolded with AI tools but has been refactored into idiomatic, component-based Svelte.
- **Contributing**: This project is in early development and the roadmap is strictly managed. Please open an issue to discuss your ideas before submitting a pull request. Unsolicited PRs may be closed without review. See [CONTRIBUTING.md](CONTRIBUTING.md) for full details.

---

## License

[GPL-3.0](LICENSE) © 2025-2026 Vigintillionn
