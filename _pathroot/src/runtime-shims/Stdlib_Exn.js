// SPDX-License-Identifier: PMPL-1.0-or-later
// Minimal Stdlib_Exn shim for Deno

export function raiseError(msg) {
  throw new Error(msg);
}
