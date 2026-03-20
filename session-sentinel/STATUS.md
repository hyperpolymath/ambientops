# Session Sentinel — Status

**Status: WIP / FAULTY**

## Known Issues

- **56 SIGABRT crashes in 4 days** (as of 2026-03-20)
- Root cause: D-Bus poll hang in `tray.zig` — no timeout on `dbus_connection_read_write_dispatch`, leading to watchdog kill
- Secondary: D-Bus session bus not ready at service start (race condition)

## Migration Plan

- **From:** AffineScript (`.as`) core
- **To:** Ephapax (`.eph`) core with linear types for D-Bus resource management
- **Keeping:** Idris2 ABI (`src/interface/abi/`) and Zig FFI (`src/interface/ffi/`)
- **Rationale:** Ephapax linear types (`let!`) enforce exactly-once resource consumption, preventing the D-Bus connection leak that causes the SIGABRT

## Disabled Locally

- Service disabled: `systemctl --user disable session-sentinel.service`
- Binary removed: `~/.local/bin/session-sentinel-tray`
- Do NOT re-enable until Ephapax rewrite is functional
