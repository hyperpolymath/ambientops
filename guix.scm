;; SPDX-License-Identifier: MPL-2.0
;; Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
;;
;; Guix development environment for ambientops.
;; Usage: guix shell -D -f guix.scm

(use-modules (guix packages)
             (guix build-system gnu)
             (gnu packages rust)
             (gnu packages crates-io)
             (gnu packages erlang)
             (gnu packages elixir)
             (gnu packages node))

(package
  (name "ambientops")
  (version "0.1.0")
  (source #f)
  (build-system gnu-build-system)
  (native-inputs
   (list rust
         rust-cargo
         elixir
         erlang
         deno))
  (synopsis "Ambient operations and system management toolkit")
  (description
   "AmbientOps is a collection of ambient operations tools including
system management, session monitoring, and personal sysadmin
utilities built with Rust, Elixir, zig, and Deno.")
  (license #f))
