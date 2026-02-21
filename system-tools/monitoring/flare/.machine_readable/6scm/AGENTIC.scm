;; SPDX-License-Identifier: PMPL-1.0-or-later
;; AGENTIC.scm - AI Agent Operational Gating
;; system-flare

(define-module (system_flare agentic)
  #:export (agentic-config))

(define agentic-config
  '((version . "1.0.0")
    (name . "system-flare")
    (entropy-budget . 0.3)
    (allowed-operations . (read analyze suggest))
    (forbidden-operations . ())
    (gating-rules . ())))
