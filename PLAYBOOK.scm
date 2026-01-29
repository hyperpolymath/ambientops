;; SPDX-License-Identifier: PMPL-1.0-or-later
;; PLAYBOOK.scm - Operational runbook for AmbientOps umbrella repo

(define playbook
  `((version . "1.0.0")
    (procedures
      ((build
         (description . "Build documentation from AsciiDoc sources")
         (command . "just build")
         (prerequisites . ("asciidoctor installed"))
         (output . "dist/html/"))
       (test
         (description . "Validate RSR compliance and SCM file syntax")
         (command . "just test")
         (prerequisites . ("guile installed"))
         (checks . ("RSR compliance" "STATE.scm syntax" "All SCM files")))
       (deploy
         (description . "Deploy documentation to GitHub Pages")
         (command . "just build-release && git subtree push --prefix dist/html origin gh-pages")
         (prerequisites . ("asciidoctor" "asciidoctor-pdf" "git"))
         (notes . "Ensure dist/html is built before pushing"))
       (validate
         (description . "Run full validation suite")
         (command . "just validate")
         (checks . ("RSR files" "STATE.scm" "All SCM files")))
       (release
         (description . "Prepare a new release")
         (steps . ("Update version in STATE.scm"
                   "Update CHANGELOG"
                   "Run just validate"
                   "Tag release: git tag -a vX.Y.Z"
                   "Push: git push --tags")))))
    (alerts
      ((scm-parse-failure
         (severity . "high")
         (description . "SCM file failed to parse")
         (action . "Check syntax with: guile -c '(primitive-load \"FILE.scm\")'"))
       (rsr-compliance-failure
         (severity . "medium")
         (description . "RSR compliance check failed")
         (action . "Run 'just validate-rsr' and fix missing files"))))
    (contacts
      ((maintainer
         (name . "Jonathan D.A. Jewell")
         (github . "@hyperpolymath")
         (role . "Lead Maintainer"))))))
