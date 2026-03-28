// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

/// RuntimeBridge — Gossamer-only IPC bridge for Network Ambulance.
///
/// Dispatches `invoke` calls to the Gossamer backend via
/// `window.__gossamer_invoke`.  The Tauri fallback path has been removed
/// now that the backend is fully migrated to Gossamer.
///
/// Priority order:
///   1. Gossamer (`window.__gossamer_invoke`)  — production runtime
///   2. Browser  (rejects with descriptive error) — dev fallback

// ---------------------------------------------------------------------------
// Raw external bindings — Gossamer IPC injected by gossamer_channel_open()
// ---------------------------------------------------------------------------

/// Gossamer runtime detection: checks for the injected IPC function.
%%raw(`
function isGossamerRuntime() {
  return typeof window !== 'undefined'
    && typeof window.__gossamer_invoke === 'function';
}
`)
@val external isGossamerRuntime: unit => bool = "isGossamerRuntime"

/// Gossamer IPC dispatch: calls the native handler registered in main.rs.
%%raw(`
function gossamerInvoke(cmd, args) {
  return window.__gossamer_invoke(cmd, args);
}
`)
@val external gossamerInvoke: (string, 'a) => promise<'b> = "gossamerInvoke"

// ---------------------------------------------------------------------------
// Runtime detection
// ---------------------------------------------------------------------------

/// The runtime currently in use.
type runtime =
  | Gossamer
  | BrowserOnly

/// Detect and return the current runtime (cached after first call).
%%raw(`
var _detectedRuntime = null;
function detectRuntime() {
  if (_detectedRuntime !== null) return _detectedRuntime;
  if (typeof window !== 'undefined' && typeof window.__gossamer_invoke === 'function') {
    _detectedRuntime = 'gossamer';
  } else {
    _detectedRuntime = 'browser';
  }
  return _detectedRuntime;
}
`)
@val external detectRuntimeRaw: unit => string = "detectRuntime"

/// Detect and return the current runtime as a typed variant.
let detectRuntime = (): runtime => {
  switch detectRuntimeRaw() {
  | "gossamer" => Gossamer
  | _ => BrowserOnly
  }
}

// ---------------------------------------------------------------------------
// Unified invoke — Gossamer or reject
// ---------------------------------------------------------------------------

/// Invoke a backend command through the Gossamer runtime.
///
/// - On Gossamer: calls `window.__gossamer_invoke(cmd, args)`
/// - On browser:  rejects with a descriptive error
///
/// This is the primary function all command modules should use.
let invoke = (cmd: string, args: 'a): promise<'b> => {
  if isGossamerRuntime() {
    gossamerInvoke(cmd, args)
  } else {
    Promise.reject(
      JsError.throwWithMessage(
        `No desktop runtime — "${cmd}" requires Gossamer`,
      ),
    )
  }
}

/// Invoke a command with no arguments.
let invokeSimple = (cmd: string): promise<'a> => {
  invoke(cmd, Obj.magic(Dict.make()))
}

/// Check whether the Gossamer desktop runtime is available.
let hasDesktopRuntime = (): bool => {
  isGossamerRuntime()
}

/// Get a human-readable name for the current runtime.
let runtimeName = (): string => {
  switch detectRuntime() {
  | Gossamer => "Gossamer"
  | BrowserOnly => "Browser"
  }
}

// ---------------------------------------------------------------------------
// Event abstraction — Gossamer events
// ---------------------------------------------------------------------------

module Event = {
  /// Listen to an event from the Gossamer backend.
  let listen = (event: string, callback: 'payload => unit): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_listen", {"event": event, "callback": callback})
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — event listening requires Gossamer",
        ),
      )
    }
  }

  /// Emit an event to the Gossamer backend.
  let emit = (event: string, payload: 'payload): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_emit", {"event": event, "payload": payload})
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — event emission requires Gossamer",
        ),
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Window abstraction — Gossamer window
// ---------------------------------------------------------------------------

module Window = {
  /// Get the current window handle.
  let getCurrent = (): promise<'window> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_get_current", {})
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window access requires Gossamer",
        ),
      )
    }
  }

  /// Set the window title.
  let setTitle = (title: string): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_set_title", {"title": title})
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window title requires Gossamer",
        ),
      )
    }
  }

  /// Minimize the current window.
  let minimize = (): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_minimize", {})
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window minimize requires Gossamer",
        ),
      )
    }
  }

  /// Maximize the current window.
  let maximize = (): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_maximize", {})
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window maximize requires Gossamer",
        ),
      )
    }
  }

  /// Close the current window.
  let close = (): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_close", {})
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window close requires Gossamer",
        ),
      )
    }
  }
}
