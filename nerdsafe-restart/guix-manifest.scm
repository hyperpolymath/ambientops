;; SPDX-License-Identifier: MPL-2.0-or-later
;; guix-manifest.scm - Reproducible shell validation environment
;;
;; This manifest captures the environment needed for nerdsafe-restart
;; validation. It provides a reproducible, isolated environment that
;; mirrors the critical components of a Fedora Kinoite system.
;;
;; Usage:
;;   guix shell -m guix-manifest.scm -- nerdsafe-restart check
;;   guix environment -m guix-manifest.scm -- nerdsafe-restart check
;;
;; To create a container:
;;   guix shell -m guix-manifest.scm --container --network -- bash
;;
;; To export as Docker image:
;;   guix pack -f docker -m guix-manifest.scm -S /bin=bin

(specifications->manifest
 '(
   ;; =========================================================================
   ;; LAYER 1: Core Shell (CRITICAL - always needed)
   ;; =========================================================================
   "bash"                    ; The shell we're validating
   "coreutils"               ; Essential utilities (ls, cat, chmod, etc.)
   "findutils"               ; find, xargs

   ;; =========================================================================
   ;; LAYER 2: Text Processing (CRITICAL - for config parsing)
   ;; =========================================================================
   "grep"                    ; Pattern matching
   "gawk"                    ; Text processing
   "sed"                     ; Stream editing
   "diffutils"               ; diff for comparing configs

   ;; =========================================================================
   ;; LAYER 3: Formal Verification (IMPORTANT - for validation)
   ;; =========================================================================
   "shellcheck"              ; Shell script static analysis

   ;; =========================================================================
   ;; LAYER 4: System Inspection (IMPORTANT - for checks)
   ;; =========================================================================
   "procps"                  ; Process utilities (ps, top)
   "util-linux"              ; System utilities (mount, etc.)
   "file"                    ; File type detection
   "which"                   ; Command location

   ;; =========================================================================
   ;; LAYER 5: Shell Enhancements (OPTIONAL - for full simulation)
   ;; =========================================================================
   ;; These are optional but recommended for realistic simulation
   "git"                     ; Version control
   "ncurses"                 ; Terminal handling

   ;; Uncomment if you use these tools:
   ;; "starship"             ; Cross-shell prompt
   ;; "zoxide"               ; Smart cd
   ;; "direnv"               ; Directory environments
   ;; "bat"                  ; Better cat
   ;; "eza"                  ; Better ls
   ;; "ripgrep"              ; Better grep
   ;; "fd"                   ; Better find

   ;; =========================================================================
   ;; LAYER 6: Language Runtimes (OPTIONAL - if your config uses them)
   ;; =========================================================================
   ;; Uncomment as needed based on your .bashrc.d configuration:

   ;; OCaml (for opam)
   ;; "ocaml"
   ;; "opam"

   ;; Rust (for cargo)
   ;; "rust"
   ;; "rust-cargo"

   ;; Haskell (for ghcup/cabal)
   ;; "ghc"
   ;; "cabal-install"

   ;; Node.js alternative (Deno)
   ;; "deno"

   ;; =========================================================================
   ;; LAYER 7: Theorem Provers (OPTIONAL - if you have theorem-provers module)
   ;; =========================================================================
   ;; "coq"
   ;; "lean"                 ; Not in Guix, use elan
   ;; "agda"
   ))
