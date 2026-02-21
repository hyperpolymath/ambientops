// SPDX-License-Identifier: PMPL-1.0-or-later
// Minimal Js_json shim for Deno

export function parseExn(str) {
  return JSON.parse(str);
}

export function stringify(json) {
  return JSON.stringify(json);
}

export function decodeString(json) {
  return typeof json === 'string' ? json : undefined;
}

export function decodeObject(json) {
  return typeof json === 'object' && json !== null && !Array.isArray(json) ? json : undefined;
}

export function decodeArray(json) {
  return Array.isArray(json) ? json : undefined;
}

export function decodeNumber(json) {
  return typeof json === 'number' ? json : undefined;
}

export function decodeBoolean(json) {
  return typeof json === 'boolean' ? json : undefined;
}

export function decodeNull(json) {
  return json === null ? null : undefined;
}
