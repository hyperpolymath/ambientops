;; SPDX-License-Identifier: MPL-2.0-or-later
;; guix-channels.scm - Guix channels for nerdsafe-restart environment
;;
;; This defines the Guix channels needed to reproduce the validation
;; environment. Use with:
;;   guix pull -C guix-channels.scm
;;   guix shell -m guix-manifest.scm

(list
 ;; Official Guix channel (pinned for reproducibility)
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  ;; Pin to a specific commit for reproducibility
  ;; Update this periodically
  (branch "master"))

 ;; Nonguix for proprietary firmware/drivers if needed
 ;; Uncomment if your system requires non-free components
 #;
 (channel
  (name 'nonguix)
  (url "https://gitlab.com/nonguix/nonguix")
  (branch "master"))

 ;; Hyperpolymath channel (custom packages)
 ;; Uncomment when available
 #;
 (channel
  (name 'hyperpolymath)
  (url "https://github.com/hyperpolymath/guix-channel")
  (branch "main")))
