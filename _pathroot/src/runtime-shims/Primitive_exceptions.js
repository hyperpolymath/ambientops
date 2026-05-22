// SPDX-License-Identifier: MPL-2.0
// Minimal Primitive_exceptions shim for Deno

export function raiseError(msg) {
  throw new Error(msg);
}
