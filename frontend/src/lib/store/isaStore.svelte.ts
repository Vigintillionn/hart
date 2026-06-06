import type { FormatInfo } from "../../bindings/FormatInfo";
import type { InstructionInfo } from "../../bindings/InstructionInfo";
import type { PseudoInfo } from "../../bindings/PseudoInfo";
import type { SyscallInfo } from "../../bindings/SyscallInfo";
import type { DirectiveInfo } from "../../bindings/DirectiveInfo";
import type { CsrInfo } from "../../bindings/CsrInfo";

class IsaStore {
  formats = $state<FormatInfo[]>([]);
  instructions = $state<InstructionInfo[]>([]);
  pseudos = $state<PseudoInfo[]>([]);
  syscalls = $state<SyscallInfo[]>([]);
  directives = $state<DirectiveInfo[]>([]);
  csrs = $state<CsrInfo[]>([]);

  public setCatalogue(
    formats: FormatInfo[],
    instructions: InstructionInfo[],
    pseudos: PseudoInfo[],
    syscalls: SyscallInfo[],
    directives: DirectiveInfo[],
    csrs: CsrInfo[],
  ) {
    this.formats = formats;
    this.instructions = instructions;
    this.pseudos = pseudos;
    this.syscalls = syscalls;
    this.directives = directives;
    this.csrs = csrs;
  }

  /** Look up a format's metadata by its id (e.g. `"r"`, `"shift"`) */
  public format(id: string): FormatInfo | undefined {
    return this.formats.find((f) => f.id === id);
  }
}

export const isaStore = new IsaStore();
