// SPDX-License-Identifier: MPL-2.0
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
