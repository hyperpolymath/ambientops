;; SPDX-License-Identifier: PMPL-1.0-or-later
;; HAR (Hybrid Automation Router) Guix Package Definition
;;
;; Install: guix install -f deploy/guix/har.scm
;; Build:   guix build -f deploy/guix/har.scm
;; Shell:   guix shell -f deploy/guix/har.scm

(define-module (har)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system mix)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages erlang)
  #:use-module (gnu packages elixir))

(define-public har
  (package
    (name "har")
    (version "1.0.0-rc1")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/hyperpolymath/hybrid-automation-router")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0000000000000000000000000000000000000000000000000000"))))
    (build-system mix-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (add-before 'build 'set-mix-env
           (lambda _
             (setenv "MIX_ENV" "prod")
             #t)))))
    (native-inputs
     (list elixir erlang))
    (propagated-inputs
     (list erlang))
    (synopsis "BGP for infrastructure automation")
    (description
     "HAR (Hybrid Automation Router) treats configuration management like
network packet routing. It parses configs from any IaC tool (Ansible, Salt,
Terraform), extracts semantic operations, and routes/transforms them to any
target format.")
    (home-page "https://github.com/hyperpolymath/hybrid-automation-router")
    (license license:mpl2.0)))

har
