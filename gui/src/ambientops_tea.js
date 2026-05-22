// SPDX-License-Identifier: MPL-2.0
// AmbientOps GUI Bridge

/**
 * Wraps the AmbientOps AffineScript Wasm module.
 */
class AmbientOpsTEA {
  constructor(exports) {
    this.exports = exports;
    this.memory = exports.memory;
  }

  init() {
    return this.exports.ambientops_init();
  }

  update(msg, model) {
    return this.exports.ambientops_update(msg, model);
  }

  view(model) {
    const ptr = this.exports.ambientops_view(model);
    return this.readString(ptr);
  }

  readString(ptr) {
    const view = new DataView(this.memory.buffer);
    const len = view.getInt32(ptr, true);
    const bytes = new Uint8Array(this.memory.buffer, ptr + 4, len);
    return new TextDecoder().decode(bytes);
  }
}

export async function load(url) {
  const response = await fetch(url);
  const bytes = await response.arrayBuffer();
  const importObject = {
    wasi_snapshot_preview1: {
      fd_write: (fd, iovs, iovs_len, nwritten) => 0
    }
  };
  const result = await WebAssembly.instantiate(bytes, importObject);
  return new AmbientOpsTEA(result.instance.exports);
}

export const Msg = {
  Navigate: (dept) => ({ tag: 0, value: dept }),
  UpdateWeather: (state, summary) => ({ tag: 1, state, summary }),
  Resize: (w, h) => ({ tag: 2, w, h })
};

// Internal Wasm tags for Msg
export const MsgTag = {
  Navigate: 0,
  UpdateWeather: 1,
  Resize: 2
};

export const Department = {
  Ward: 0,
  EmergencyRoom: 1,
  OperatingRoom: 2,
  Records: 3
};

export const WeatherState = {
  Calm: 0,
  Watch: 1,
  Act: 2
};
