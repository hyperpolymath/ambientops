// SPDX-License-Identifier: PMPL-1.0-or-later
// Minimal Js_dict shim for Deno

export function get(dict, key) {
  return dict[key];
}

export function entries(dict) {
  return Object.entries(dict);
}

export function keys(dict) {
  return Object.keys(dict);
}

export function values(dict) {
  return Object.values(dict);
}
