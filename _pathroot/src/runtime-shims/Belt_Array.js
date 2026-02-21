// SPDX-License-Identifier: PMPL-1.0-or-later
// Minimal Belt_Array shim for Deno

export function concat(a, b) {
  return a.concat(b);
}

export function map(arr, f) {
  return arr.map(f);
}

export function get(arr, index) {
  return arr[index];
}

export function getExn(arr, index) {
  if (index >= arr.length || index < 0) {
    throw new Error(`Array index out of bounds: ${index}`);
  }
  return arr[index];
}

export function sliceToEnd(arr, start) {
  return arr.slice(start);
}

export function length(arr) {
  return arr.length;
}

export function forEach(arr, f) {
  arr.forEach(f);
}
