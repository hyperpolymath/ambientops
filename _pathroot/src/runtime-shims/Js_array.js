// SPDX-License-Identifier: MPL-2.0
// Minimal Js_array shim for Deno

export function push(arr, item) {
  arr.push(item);
}

export function concat(a, b) {
  return a.concat(b);
}

export function map(f, arr) {
  return arr.map(f);
}

export function forEach(f, arr) {
  arr.forEach(f);
}
