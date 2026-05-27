use serde::{Deserialize, Serialize};
use ts_rs::TS;

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
pub struct CpuState {
    pub pc: u32,
    pub regs: Vec<i32>,
    pub cycles: usize,
    pub status: String,
    pub csrs: Vec<(u32, u32)>,
    pub mem: Vec<(u64, u8)>,
    #[serde(rename = "heapTop")]
    pub heap_top: u32,
}

#[derive(Serialize, Deserialize, TS, Clone, Debug)]
#[ts(export, export_to = "../src/bindings/")]
#[serde(tag = "type", content = "data")]
pub enum EmulatorResponse {
    #[serde(rename = "state")]
    State(CpuState),
    #[serde(rename = "error")]
    Error(String),
}
