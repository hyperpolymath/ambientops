// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

/// RuntimeBridge — Unified IPC bridge for Network Ambulance.
///
/// Detects the available runtime (Gossamer, Tauri, or browser-only) and
/// dispatches `invoke` calls to the appropriate backend. This allows all
/// command modules to use a single import instead of binding directly
/// to `@tauri-apps/api/core`.
///
/// Priority order:
///   1. Gossamer (`window.__gossamer_invoke`)  — own stack, preferred
///   2. Tauri    (`window.__TAURI_INTERNALS__`) — legacy, transition
///   3. Browser  (direct HTTP fetch)            — development fallback
///
/// Migration path: command files replace
///   `@module("@tauri-apps/api/core") external invoke: ...`
/// with
///   `let invoke = RuntimeBridge.invoke`

// ---------------------------------------------------------------------------
// Raw external bindings — exactly one of these will be available at runtime
// ---------------------------------------------------------------------------

/// Gossamer IPC: injected by gossamer_channel_open() into the webview.
/// Signature: (commandName: string, payload: object) => Promise<any>
%%raw(`
function isGossamerRuntime() {
  return typeof window !== 'undefined'
    && typeof window.__gossamer_invoke === 'function';
}
`)
@val external isGossamerRuntime: unit => bool = "isGossamerRuntime"

%%raw(`
function gossamerInvoke(cmd, args) {
  return window.__gossamer_invoke(cmd, args);
}
`)
@val external gossamerInvoke: (string, 'a) => promise<'b> = "gossamerInvoke"

/// Tauri IPC: injected by the Tauri runtime into the webview.
%%raw(`
function isTauriRuntime() {
  return typeof window !== 'undefined'
    && window.__TAURI_INTERNALS__ != null
    && !window.__TAURI_INTERNALS__.__BROWSER_SHIM__;
}
`)
@val external isTauriRuntime: unit => bool = "isTauriRuntime"

@module("@tauri-apps/api/core")
external tauriInvoke: (string, 'a) => promise<'b> = "invoke"

// ---------------------------------------------------------------------------
// Unified invoke — detects runtime and dispatches
// ---------------------------------------------------------------------------

/// The runtime currently in use. Cached after first detection for performance.
type runtime =
  | Gossamer
  | Tauri
  | BrowserOnly

%%raw(`
var _detectedRuntime = null;
function detectRuntime() {
  if (_detectedRuntime !== null) return _detectedRuntime;
  if (typeof window !== 'undefined' && typeof window.__gossamer_invoke === 'function') {
    _detectedRuntime = 'gossamer';
  } else if (typeof window !== 'undefined' && window.__TAURI_INTERNALS__ != null && !window.__TAURI_INTERNALS__.__BROWSER_SHIM__) {
    _detectedRuntime = 'tauri';
  } else {
    _detectedRuntime = 'browser';
  }
  return _detectedRuntime;
}
`)
@val external detectRuntimeRaw: unit => string = "detectRuntime"

/// Detect and return the current runtime.
let detectRuntime = (): runtime => {
  switch detectRuntimeRaw() {
  | "gossamer" => Gossamer
  | "tauri" => Tauri
  | _ => BrowserOnly
  }
}

/// Invoke a backend command through whatever runtime is available.
///
/// - On Gossamer: calls `window.__gossamer_invoke(cmd, args)`
/// - On Tauri:    calls `window.__TAURI_INTERNALS__.invoke(cmd, args)`
/// - On browser:  rejects with a descriptive error
///
/// This is the primary function all command modules should use.
let invoke = (cmd: string, args: 'a): promise<'b> => {
  if isGossamerRuntime() {
    gossamerInvoke(cmd, args)
  } else if isTauriRuntime() {
    tauriInvoke(cmd, args)
  } else {
    Promise.reject(
      JsError.throwWithMessage(
        `No desktop runtime — "${cmd}" requires Gossamer or Tauri`,
      ),
    )
  }
}

/// Invoke a command with no arguments.
let invokeSimple = (cmd: string): promise<'a> => {
  invoke(cmd, Obj.magic(Dict.make()))
}

/// Check whether any desktop runtime is available.
let hasDesktopRuntime = (): bool => {
  isGossamerRuntime() || isTauriRuntime()
}

/// Get a human-readable name for the current runtime.
let runtimeName = (): string => {
  switch detectRuntime() {
  | Gossamer => "Gossamer"
  | Tauri => "Tauri"
  | BrowserOnly => "Browser"
  }
}

// ---------------------------------------------------------------------------
// Event abstraction — Gossamer events vs Tauri events
// ---------------------------------------------------------------------------

module Event = {
  @module("@tauri-apps/api/event")
  external tauriListen: (string, 'payload => unit) => promise<unit> = "listen"

  @module("@tauri-apps/api/event")
  external tauriEmit: (string, 'payload) => promise<unit> = "emit"

  /// Listen to an event from the backend.
  /// On Gossamer, routes through IPC to __gossamer_event_listen.
  /// On Tauri, uses the native event API.
  let listen = (event: string, callback: 'payload => unit): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_listen", {"event": event, "callback": callback})
    } else if isTauriRuntime() {
      tauriListen(event, callback)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — event listening requires Gossamer or Tauri",
        ),
      )
    }
  }

  /// Emit an event to the backend.
  /// On Gossamer, routes through IPC to __gossamer_event_emit.
  /// On Tauri, uses the native event API.
  let emit = (event: string, payload: 'payload): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_emit", {"event": event, "payload": payload})
    } else if isTauriRuntime() {
      tauriEmit(event, payload)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — event emission requires Gossamer or Tauri",
        ),
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Window abstraction — Gossamer window vs Tauri window
// ---------------------------------------------------------------------------

module Window = {
  @module("@tauri-apps/api/window")
  external tauriGetCurrentWindow: unit => 'window = "getCurrent"

  /// Get the current window handle.
  /// On Gossamer, routes through IPC to __gossamer_window_get_current.
  /// On Tauri, uses the native window API.
  let getCurrent = (): promise<'window> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_get_current", {})
    } else if isTauriRuntime() {
      Promise.resolve(tauriGetCurrentWindow())
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window access requires Gossamer or Tauri",
        ),
      )
    }
  }

  /// Set the window title.
  let setTitle = (title: string): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_set_title", {"title": title})
    } else if isTauriRuntime() {
      let win = tauriGetCurrentWindow()
      Obj.magic(win)["setTitle"](title)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window title requires Gossamer or Tauri",
        ),
      )
    }
  }

  /// Minimize the current window.
  let minimize = (): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_minimize", {})
    } else if isTauriRuntime() {
      let win = tauriGetCurrentWindow()
      Obj.magic(win)["minimize"]()
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window minimize requires Gossamer or Tauri",
        ),
      )
    }
  }

  /// Maximize the current window.
  let maximize = (): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_maximize", {})
    } else if isTauriRuntime() {
      let win = tauriGetCurrentWindow()
      Obj.magic(win)["maximize"]()
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window maximize requires Gossamer or Tauri",
        ),
      )
    }
  }

  /// Close the current window.
  let close = (): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_window_close", {})
    } else if isTauriRuntime() {
      let win = tauriGetCurrentWindow()
      Obj.magic(win)["close"]()
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — window close requires Gossamer or Tauri",
        ),
      )
    }
  }
}
