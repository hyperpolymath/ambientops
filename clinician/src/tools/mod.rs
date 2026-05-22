// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! System administration tools - Sysinternals-like functionality for Linux.
//!
//! Each module implements a focused administrative capability. Modules are
//! designed for CLI dispatch from `main.rs` and can also be used as library
//! functions from other crates.

pub mod process;
pub mod network;
pub mod disk;
pub mod service;
pub mod security;
pub mod monitor;
pub mod health;
pub mod crisis;
pub mod bt_sentinel;
pub mod ipfs;
pub mod cache_layer;
