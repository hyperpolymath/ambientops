;;; SPDX-License-Identifier: PMPL-1.0-or-later
;;; guix.scm - GNU Guix package definition for System Operating Theatre

(use-modules (guix packages)
             (guix git-download)
             (guix build-system gnu)
             ((guix licenses) #:prefix license:)
             (gnu packages dlang))

(define-public operating-theatre
  (package
    (name "operating-theatre")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/hyperpolymath/system-operating-theatre")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (native-inputs
     (list ldc dub))
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (replace 'build
           (lambda _
             (invoke "dub" "build" "--build=release")))
         (replace 'install
           (lambda* (#:key outputs #:allow-other-keys)
             (let ((bin (string-append (assoc-ref outputs "out") "/bin")))
               (install-file "sor" bin)))))))
    (home-page "https://github.com/hyperpolymath/system-operating-theatre")
    (synopsis "Plan-first system management tool")
    (description
     "System Operating Theatre is a plan-first system management and hardening
tool. It follows the scan→plan→apply→undo→receipt workflow to ensure safe,
auditable system changes. Part of the AmbientOps ecosystem.")
    (license license:agpl3+)))

operating-theatre
