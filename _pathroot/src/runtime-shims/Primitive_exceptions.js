// SPDX-License-Identifier: PMPL-1.0-or-later
// Minimal Primitive_exceptions shim for Deno

export function raiseError(msg) {
  throw new Error(msg);
}
