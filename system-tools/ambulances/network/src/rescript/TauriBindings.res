// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// TauriBindings.res — Tauri IPC bindings for Network Ambulance.
//
// Now delegates to RuntimeBridge for runtime-agnostic command dispatch.
// Commands work transparently on both Gossamer and Tauri runtimes.
// The original @tauri-apps/api imports are preserved as fallback paths
// inside RuntimeBridge.

// ---------------------------------------------------------------------------
// Command wrappers — use RuntimeBridge.invoke for runtime detection
// ---------------------------------------------------------------------------

/// Run network diagnostics. Dispatches to the backend via Gossamer or Tauri.
let runDiagnostics = (): promise<Types.diagnosticResult> => {
  RuntimeBridge.invokeSimple("run_diagnostics")
}

/// Run a targeted repair. Dispatches to the backend via Gossamer or Tauri.
let runRepair = (target: string): promise<Types.repairResult> => {
  RuntimeBridge.invoke("run_repair", {"target": target})
}

/// Check if running with elevated privileges.
let checkPrivileges = (): promise<bool> => {
  RuntimeBridge.invokeSimple("check_privileges")
}

/// Get platform information string.
let getPlatformInfo = (): promise<string> => {
  RuntimeBridge.invokeSimple("get_platform_info")
}

// ---------------------------------------------------------------------------
// Event wrappers — delegate to RuntimeBridge.Event
// ---------------------------------------------------------------------------

/// Listen to a backend event (works on both Gossamer and Tauri).
let listen = (event: string, callback: 'payload => unit): promise<unit> => {
  RuntimeBridge.Event.listen(event, callback)
}

/// Emit an event to the backend (works on both Gossamer and Tauri).
let emit = (event: string, payload: 'payload): promise<unit> => {
  RuntimeBridge.Event.emit(event, payload)
}

// ---------------------------------------------------------------------------
// Window wrappers — delegate to RuntimeBridge.Window
// ---------------------------------------------------------------------------

/// Set the window title (works on both Gossamer and Tauri).
let setWindowTitle = (title: string): promise<unit> => {
  RuntimeBridge.Window.setTitle(title)
}

/// Minimize the current window.
let minimizeWindow = (): promise<unit> => {
  RuntimeBridge.Window.minimize()
}

/// Maximize the current window.
let maximizeWindow = (): promise<unit> => {
  RuntimeBridge.Window.maximize()
}

/// Close the current window.
let closeWindow = (): promise<unit> => {
  RuntimeBridge.Window.close()
}
