;; SPDX-License-Identifier: PMPL-1.0-or-later
;; HAR Guix Channel Definition
;;
;; Add to ~/.config/guix/channels.scm:
;;   (cons (channel
;;           (name 'har)
;;           (url "https://github.com/hyperpolymath/hybrid-automation-router")
;;           (branch "main")
;;           (introduction
;;             (make-channel-introduction
;;               "COMMIT_HASH_HERE"
;;               (openpgp-fingerprint "YOUR_GPG_FINGERPRINT_HERE"))))
;;         %default-channels)

(list
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  (branch "master")
  (introduction
   (make-channel-introduction
    "9edb3f66fd807b096b48283debdcddccfea34bad"
    (openpgp-fingerprint
     "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
 (channel
  (name 'har)
  (url "https://github.com/hyperpolymath/hybrid-automation-router")
  (branch "main")))
