#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod types;

use std::sync::Mutex;
use tauri::{Emitter, Manager};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;
use types::EmulatorResponse;

struct EmulatorState {
    child: Mutex<Option<CommandChild>>,
}

#[tauri::command]
fn send_command(state: tauri::State<'_, EmulatorState>, cmd: String) -> Result<(), String> {
    let mut child_guard = state.child.lock().unwrap();
    if let Some(child) = child_guard.as_mut() {
        let payload = format!("{}\n", cmd);
        child.write(payload.as_bytes()).map_err(|e| e.to_string())?;
    } else {
        eprintln!("Warning: Tried to send command but Haskell sidecar is not running!");
    }
    Ok(())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(EmulatorState {
            child: Mutex::new(None),
        })
        .setup(|app| {
            println!("Spawning Haskell Emulator...");

            let (mut rx, child) = app
                .shell()
                .sidecar("riscv")
                .expect("Failed to create sidecar command")
                .args(["--rpc", "dummy.s"])
                .spawn()
                .expect("Failed to spawn sidecar");

            let state = app.state::<EmulatorState>();
            *state.child.lock().unwrap() = Some(child);

            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                while let Some(event) = rx.recv().await {
                    if let CommandEvent::Stdout(line) = event {
                        let json_str = String::from_utf8(line).unwrap();

                        match serde_json::from_str::<EmulatorResponse>(&json_str) {
                            Ok(response) => {
                                app_handle.emit("emulator-update", response).unwrap();
                            }
                            Err(e) => {
                                eprintln!("Failed to parse Haskell JSON: {}\nRaw: {}", e, json_str);
                            }
                        }
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![send_command])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
