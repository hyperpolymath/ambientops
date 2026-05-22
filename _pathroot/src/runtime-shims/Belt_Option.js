// SPDX-License-Identifier: MPL-2.0
// Minimal Belt_Option shim for Deno

export function getExn(opt) {
  if (opt === undefined || opt === null) {
    throw new Error("getExn called on None");
  }
  return opt;
}

export function isSome(opt) {
  return opt !== undefined && opt !== null;
}

export function isNone(opt) {
  return opt === undefined || opt === null;
}

export function getWithDefault(opt, def) {
  return opt !== undefined && opt !== null ? opt : def;
}

export function map(opt, f) {
  if (opt === undefined || opt === null) {
    return undefined;
  }
  return f(opt);
}
