#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod types;

use std::sync::Mutex;
use tauri::{Emitter, Manager, RunEvent};
use tauri_plugin_shell::process::{CommandChild, CommandEvent};
use tauri_plugin_shell::ShellExt;
use types::EmulatorResponse;

struct EmulatorState {
    child: Mutex<Option<CommandChild>>,
}

#[tauri::command]
fn send_command(state: tauri::State<'_, EmulatorState>, cmd: String) -> Result<(), String> {
    let mut child_guard = state.child.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(child) = child_guard.as_mut() {
        let payload = format!("{}\n", cmd);
        child.write(payload.as_bytes()).map_err(|e| e.to_string())?;
    } else {
        eprintln!("Warning: Tried to send command but Haskell sidecar is not running!");
    }
    Ok(())
}

/// Work around a Tauri AppImage packaging bug on Wayland.
///
/// The AppImage bundles its own (older) `libwayland-client.so.0`, which shadows
/// the host's via the AppRun-set `LD_LIBRARY_PATH`. Modern Mesa on the host
/// must use the host's matching `libwayland-client` to create an EGL display;
/// with the bundled one, `eglGetPlatformDisplay` fails and WebKitGTK aborts with
/// "Could not create default EGL display: EGL_BAD_PARAMETER" before any window
/// appears. `libwayland-client` is on the AppImage excludelist for exactly this
/// reason, but Tauri's bundler ships it anyway.
///
/// Fix: when launched from an AppImage on a Wayland session, re-exec ourselves
/// once with the host's `libwayland-client.so.0` in `LD_PRELOAD` so it wins over
/// the bundled copy. This is a no-op for native installs (deb/rpm/dev), pure-X11
/// sessions, and systems without a host `libwayland-client`.
#[cfg(target_os = "linux")]
fn preload_system_wayland_if_appimage() {
    use std::os::unix::process::CommandExt;

    if std::env::var_os("APPIMAGE").is_none() {
        return;
    }
    if std::env::var_os("WAYLAND_DISPLAY").is_none() {
        return;
    }
    if std::env::var_os("HART_WAYLAND_PRELOADED").is_some() {
        return;
    }

    let host_lib = [
        "/usr/lib/x86_64-linux-gnu/libwayland-client.so.0",
        "/usr/lib64/libwayland-client.so.0",
        "/usr/lib/libwayland-client.so.0",
        "/lib/x86_64-linux-gnu/libwayland-client.so.0",
    ]
    .into_iter()
    .find(|p| std::path::Path::new(p).exists());
    let Some(host_lib) = host_lib else {
        return;
    };

    let preload = match std::env::var_os("LD_PRELOAD") {
        Some(existing) if !existing.is_empty() => {
            let mut s = std::ffi::OsString::from(host_lib);
            s.push(":");
            s.push(existing);
            s
        }
        _ => std::ffi::OsString::from(host_lib),
    };

    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let err = std::process::Command::new(exe)
        .args(std::env::args_os().skip(1))
        .env("LD_PRELOAD", preload)
        .env("HART_WAYLAND_PRELOADED", "1")
        .exec(); // returns only if exec failed
    eprintln!("Failed to re-exec with host libwayland-client preloaded: {err}");
}

fn main() {
    #[cfg(target_os = "linux")]
    preload_system_wayland_if_appimage();

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
                .sidecar("hart-emulator")
                .expect("Failed to create sidecar command")
                .args(["--rpc", "dummy.s"])
                .spawn()
                .expect("Failed to spawn sidecar");

            let state = app.state::<EmulatorState>();
            *state.child.lock().unwrap_or_else(|e| e.into_inner()) = Some(child);

            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                while let Some(event) = rx.recv().await {
                    match event {
                        CommandEvent::Stdout(line) => {
                            let json_str = String::from_utf8_lossy(&line);

                            match serde_json::from_str::<EmulatorResponse>(&json_str) {
                                Ok(response) => {
                                    if let Err(e) = app_handle.emit("emulator-update", response) {
                                        eprintln!("Failed to emit emulator-update: {}", e);
                                    }
                                }
                                Err(e) => {
                                    eprintln!(
                                        "Failed to parse Haskell JSON: {}\nRaw: {}",
                                        e, json_str
                                    );
                                }
                            }
                        }
                        CommandEvent::Terminated(payload) => {
                            eprintln!("Haskell sidecar terminated with code: {:?}", payload.code);
                            *app_handle
                                .state::<EmulatorState>()
                                .child
                                .lock()
                                .unwrap_or_else(|e| e.into_inner()) = None;
                            let _ = app_handle.emit("sidecar-exit", payload.code);
                        }
                        _ => {}
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![send_command])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if let RunEvent::ExitRequested { .. } = event {
                let child_to_kill = app_handle
                    .state::<EmulatorState>()
                    .child
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .take();

                if let Some(child) = child_to_kill {
                    let _ = child.kill();
                    println!("Haskell sidecar safely terminated on exit.");
                }
            }
        });
}
