// SPDX-License-Identifier: MPL-2.0
// Minimal Stdlib_Exn shim for Deno

export function raiseError(msg) {
  throw new Error(msg);
}
