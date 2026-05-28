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
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(tag = "type")]
pub enum EmulatorResponse {
    #[serde(rename = "state")]
    State { data: CpuState },
    #[serde(rename = "loaded")]
    Loaded {
        state: CpuState,
        #[serde(rename = "sourceMap")]
        source_map: Vec<(u32, u32)>,
    },
    #[serde(rename = "error")]
    Error { message: String },
    #[serde(rename = "need_input")]
    NeedInput,
}
