# hart-emulator

The Haskell backend of [HART](../README.md): a from-scratch **RV32IM**
assembler, emulator, and time-travel debugger. It runs as a standalone CLI and
as the RPC daemon that the desktop app drives as a sidecar.

Haskell (GHC2021, GHC ≥ 9.6, Cabal ≥ 3.12). Incomplete pattern/record matches
are build errors (`-Werror=incomplete-*`), so GADT matches stay exhaustive.

## Commands

Run from `emulator/`:

```bash
cabal build                          # build the library + executable
cabal run hart-emulator -- prog.s    # CLI: assemble, run, then a debugger REPL
cabal run hart-emulator -- --rpc x.s # RPC daemon (what the frontend spawns)
cabal test                           # hspec + QuickCheck suite
```

The frontend won't pick up backend changes until you rebuild and recopy the
sidecar (`pnpm build-sidecar` from `frontend/`).

## Pipeline

A program flows `String → Statements → Executable → CPU memory`:

```
Parser.parse  ->  Linker.resolve ->  CPU.loadProgram  ->  execute
```

- **`Parser`** turns source into `Statement`s (instructions, pseudo-instructions,
  directives) and resolves register ABI names.
- **`Linker`** lowers pseudo-instructions (`li → lui + addi`, `ret → jalr`, …),
  resolves labels to addresses, and builds the address->source-line map that
  drives editor highlighting.
- **`CPU.loadProgram`** assembles each instruction to a `Word32` and lays out
  program + data in memory.

Instructions are modeled by a phase-indexed GADT in `Types`: the type carries
both the RISC-V format (R/I/S/B/U/J/Sys) and the compilation phase, and a type
family picks the immediate representation per phase (a label/relocation before
linking, a plain `Int` after). The upshot is that a label _can't_ reach the
assembler or decoder: it's a type error, not a runtime check. Encode/decode is
covered by a `decode . assemble == id` QuickCheck property.

## Extensions

Extensions are modular. `Extension` is the registry (the `Extension` enum, the
enabled `ExtensionSet`, and per-extension metadata), and `Extension.Classify`
assigns every opcode to exactly one extension. The parser only accepts mnemonics
from enabled extensions, and the decoder rejects disabled ones, so turning an
extension off means it doesn't parse, assemble, or run. The base `I` set is
mandatory.

## Modules

| Module                            | Responsibility                                                  |
| --------------------------------- | --------------------------------------------------------------- |
| `Types`                           | Phase-indexed `Instruction` GADT, op enums, `Operand`           |
| `Parser`                          | Source text → `Statement`s                                      |
| `Linker`                          | Lower pseudo-instructions, resolve labels, build the source map |
| `Assembler` / `Decoder`           | `Instruction <-> Word32`                                        |
| `ISA`                             | Opcode / funct encoding tables                                  |
| `Extension`, `Extension.Classify` | Extension registry + opcode classification                      |
| `Doc`                             | Self-describing instruction reference (`OpDoc` typeclass)       |
| `Machine`                         | `CPU` state, the `MonadCPU` effect class, memory & trap helpers |
| `CPU`                             | Per-instruction execution; `step` does fetch → decode → execute |
| `Kernel`                          | `ecall` syscall ABI (dispatched on `a7`)                        |
| `Debugger`                        | Time-travel trace; a zipper over recorded `CPU` states          |
| `Error` / `Render`                | Typed errors and their human-readable rendering                 |
| `app/{Main,CLI,RPC}.hs`           | Entry points                                                    |

## RPC protocol

`app/RPC.hs` speaks line-delimited JSON over stdin/stdout, one object per line.
Commands include `load`, `run`, `pause`, `step_forward`, `step_back`, `rewind`,
`input`, `set_breakpoints`, `set_extensions`, and `get_instruction_set`;
responses include `state`, `loaded`, `error`, `extensions`, `instruction_set`,
and `need_input`. The `instruction_set` response carries the self-describing
instruction reference (formats, instructions, pseudo-instructions) built from
`lib/Doc.hs`.
