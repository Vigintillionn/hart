use serde::{Deserialize, Serialize};
use ts_rs::TS;

#[derive(Serialize, Deserialize, TS, Clone, Debug, PartialEq)]
#[ts(export, export_to = "../src/bindings/")]
pub enum CpuStatus {
    Running,
    Halted,
    Paused,
    WaitingForInput,
}

#[derive(Serialize, Deserialize, TS, Clone, Debug, PartialEq)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Info,
    Warning,
    Error,
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(tag = "kind")]
pub enum AssemblyError {
    UnknownInstruction {
        text: String,
    },
    InvalidRegister {
        text: String,
    },
    ImmediateTooLarge {
        value: i32,
    },
    UnexpectedChar {
        char: String,
    },
    EmptyParserFailed,
    ParserFail {
        text: String,
    },
    #[serde(rename = "EOF")]
    Eof,
    Located {
        line: i32,
        error: Box<AssemblyError>,
    },
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(tag = "kind")]
pub enum LinkError {
    DuplicateLabel {
        label: String,
    },
    UndefinedLabel {
        label: String,
    },
    ShiftOutOfRange {
        value: i32,
    },
    ImmOutOfRange {
        context: String,
        lo: i32,
        hi: i32,
        value: i32,
    },
    MisalignedTarget {
        context: String,
        value: i32,
    },
    Located {
        line: i32,
        error: Box<LinkError>,
    },
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(tag = "kind")]
pub enum EmulatorError {
    ParseError {
        error: AssemblyError,
    },
    LinkError {
        error: LinkError,
    },
    DecodeError {
        pc: u32,
        raw: u32,
    },
    IllegalInstruction {
        pc: u32,
        raw: u32,
    },
    InstrMisaligned {
        pc: u32,
        target: u32,
    },
    LoadMisaligned {
        pc: u32,
        address: u32,
    },
    StoreMisaligned {
        pc: u32,
        address: u32,
    },
    UnknownSyscall {
        pc: u32,
        syscall: u32,
    },
    OutOfMemory {
        address: u32,
    },
    InvalidInput {
        pc: u32,
        input: String,
    },
    Located {
        line: i32,
        error: Box<EmulatorError>,
    },
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(tag = "kind")]
pub enum Notice {
    ProgramExitedNormally,
    /// `code` is the POSIX exit status (low 8 bits of a0); `raw` is the full a0
    /// register value the program returned.
    ProgramExited { code: u32, raw: u32 },
    BreakpointHit,
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
pub struct SystemEvent {
    pub severity: Severity,
    #[serde(default)]
    pub fault: Option<EmulatorError>,
    #[serde(default)]
    pub notice: Option<Notice>,
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
pub struct CpuState {
    pub pc: u32,
    pub regs: Vec<i32>,
    pub cycles: usize,
    pub status: CpuStatus,
    pub csrs: Vec<(u32, u32)>,
    pub mem: Vec<(u64, u8)>,
    #[serde(rename = "heapTop")]
    pub heap_top: u32,
    #[serde(rename = "outputBuffer")]
    pub output_buffer: String,
    #[serde(rename = "systemLog", default)]
    pub system_log: Vec<SystemEvent>,
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(tag = "type")]
pub enum EmulatorResponse {
    #[serde(rename = "state")]
    State { data: CpuState },
    #[serde(rename = "state_delta")]
    StateDelta {
        pc: u32,
        regs: Vec<i32>,
        csrs: Vec<(u32, u32)>,
        cycles: usize,
        status: CpuStatus,
        #[serde(rename = "heapTop")]
        heap_top: u32,
        #[serde(rename = "systemLog", default)]
        system_log: Vec<SystemEvent>,
        #[serde(rename = "memDelta")]
        mem_delta: Vec<(u64, u8)>,
        #[serde(rename = "outputAppend")]
        output_append: String,
    },
    #[serde(rename = "loaded")]
    Loaded {
        state: CpuState,
        #[serde(rename = "sourceMap")]
        source_map: Vec<(u32, u32)>,
        #[serde(rename = "disasmMap")]
        disasm_map: Vec<(u32, String)>,
        #[serde(rename = "codeMap")]
        code_map: Vec<(u32, u32)>,
    },
    #[serde(rename = "error")]
    Error {
        #[serde(default)]
        message: Option<String>,
        #[serde(default)]
        source: Option<String>,
        #[serde(default)]
        error: Option<EmulatorError>,
    },
    #[serde(rename = "log")]
    Log {
        severity: Severity,
        tag: String,
        message: String,
    },
    #[serde(rename = "need_input")]
    NeedInput,
}
