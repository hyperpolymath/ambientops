// SPDX-License-Identifier: AGPL-3.0-or-later
//! Rust shim for systemd - exposes sd-bus and sd-journal via C ABI
//!
//! This allows Zig to use systemd without @cImport by providing
//! stable wrapper functions.

use libc::{c_char, c_int};
use std::ffi::{CStr, CString};
use std::ptr;

// We use raw libsystemd bindings for low-level access
// The libsystemd crate provides safe wrappers, but we need raw pointers for FFI

mod raw {
    use libc::{c_char, c_int, c_void, size_t};

    // Opaque types
    pub enum sd_bus {}
    pub enum sd_bus_message {}
    pub enum sd_journal {}

    #[repr(C)]
    pub struct sd_bus_error {
        pub name: *const c_char,
        pub message: *const c_char,
        pub need_free: c_int,
    }

    impl Default for sd_bus_error {
        fn default() -> Self {
            sd_bus_error {
                name: ptr::null(),
                message: ptr::null(),
                need_free: 0,
            }
        }
    }

    use std::ptr;

    #[link(name = "systemd")]
    extern "C" {
        pub fn sd_bus_open_system(bus: *mut *mut sd_bus) -> c_int;
        pub fn sd_bus_unref(bus: *mut sd_bus) -> *mut sd_bus;
        pub fn sd_bus_get_property_string(
            bus: *mut sd_bus,
            destination: *const c_char,
            path: *const c_char,
            interface: *const c_char,
            member: *const c_char,
            error: *mut sd_bus_error,
            ret: *mut *mut c_char,
        ) -> c_int;
        pub fn sd_bus_error_free(e: *mut sd_bus_error);

        pub fn sd_journal_open(ret: *mut *mut sd_journal, flags: c_int) -> c_int;
        pub fn sd_journal_close(j: *mut sd_journal);
        pub fn sd_journal_add_match(
            j: *mut sd_journal,
            data: *const c_void,
            size: size_t,
        ) -> c_int;
        pub fn sd_journal_seek_tail(j: *mut sd_journal) -> c_int;
        pub fn sd_journal_previous(j: *mut sd_journal) -> c_int;
        pub fn sd_journal_next(j: *mut sd_journal) -> c_int;
        pub fn sd_journal_get_data(
            j: *mut sd_journal,
            field: *const c_char,
            data: *mut *const c_void,
            length: *mut size_t,
        ) -> c_int;
    }
}

// =============================================================================
// sd-bus shim functions
// =============================================================================

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_bus_open_system(bus: *mut *mut raw::sd_bus) -> c_int {
    raw::sd_bus_open_system(bus)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_bus_unref(bus: *mut raw::sd_bus) -> *mut raw::sd_bus {
    raw::sd_bus_unref(bus)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_bus_get_property_string(
    bus: *mut raw::sd_bus,
    destination: *const c_char,
    path: *const c_char,
    interface: *const c_char,
    member: *const c_char,
    error: *mut raw::sd_bus_error,
    ret: *mut *mut c_char,
) -> c_int {
    raw::sd_bus_get_property_string(bus, destination, path, interface, member, error, ret)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_bus_error_free(e: *mut raw::sd_bus_error) {
    raw::sd_bus_error_free(e)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_free_string(s: *mut c_char) {
    if !s.is_null() {
        libc::free(s as *mut libc::c_void);
    }
}

// =============================================================================
// sd-journal shim functions
// =============================================================================

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_journal_open(
    journal: *mut *mut raw::sd_journal,
    flags: c_int,
) -> c_int {
    raw::sd_journal_open(journal, flags)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_journal_close(journal: *mut raw::sd_journal) {
    raw::sd_journal_close(journal)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_journal_add_match(
    journal: *mut raw::sd_journal,
    data: *const u8,
    len: usize,
) -> c_int {
    raw::sd_journal_add_match(journal, data as *const libc::c_void, len)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_journal_seek_tail(journal: *mut raw::sd_journal) -> c_int {
    raw::sd_journal_seek_tail(journal)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_journal_previous(journal: *mut raw::sd_journal) -> c_int {
    raw::sd_journal_previous(journal)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_journal_next(journal: *mut raw::sd_journal) -> c_int {
    raw::sd_journal_next(journal)
}

#[no_mangle]
pub unsafe extern "C" fn systemd_shim_journal_get_data(
    journal: *mut raw::sd_journal,
    field: *const c_char,
    data: *mut *const u8,
    len: *mut usize,
) -> c_int {
    raw::sd_journal_get_data(
        journal,
        field,
        data as *mut *const libc::c_void,
        len,
    )
}
