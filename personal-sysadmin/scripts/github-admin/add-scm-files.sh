#!/bin/bash
# Add SCM files to all repos

OWNER="hyperpolymath"

create_meta() {
    local repo=$1
    cat << 'EOF'
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; META.scm - Project metadata and architectural decisions

(define project-meta
  `((version . "1.0.0")
    (architecture-decisions . ())
    (development-practices
      ((code-style . "rescript")
       (security . "openssf-scorecard")
       (testing . "property-based")
       (versioning . "semver")
       (documentation . "asciidoc")
       (branching . "trunk-based")))
    (design-rationale . ())))
EOF
}

create_ecosystem() {
    local repo=$1
    local name=$(echo "$repo" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
    cat << EOF
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; ECOSYSTEM.scm - Project ecosystem positioning

(ecosystem
  ((version . "1.0.0")
   (name . "$name")
   (type . "component")
   (purpose . "Part of hyperpolymath ecosystem")
   (position-in-ecosystem . "supporting")
   (related-projects
     ((rhodium-standard . "sibling-standard")
      (gitvisor . "infrastructure")))
   (what-this-is . ("A hyperpolymath project"))
   (what-this-is-not . ("A standalone solution"))))
EOF
}

create_state() {
    local repo=$1
    local name=$(echo "$repo" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
    cat << EOF
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; STATE.scm - Current project state

(define project-state
  \`((metadata
      ((version . "1.0.0")
       (schema-version . "1")
       (created . "$(date -Iseconds)")
       (updated . "$(date -Iseconds)")
       (project . "$name")
       (repo . "$repo")))
    (current-position
      ((phase . "initial")
       (overall-completion . 0)
       (working-features . ())))
    (route-to-mvp
      ((milestones
        ((v0.1 . ((items . ("Initial setup"))))))))
    (blockers-and-issues . ())
    (critical-next-actions
      ((immediate . ())
       (this-week . ())
       (this-month . ())))))
EOF
}

create_playbook() {
    cat << 'EOF'
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; PLAYBOOK.scm - Operational runbook

(define playbook
  `((version . "1.0.0")
    (procedures
      ((deploy . (("build" . "just build")
                  ("test" . "just test")
                  ("release" . "just release")))
       (rollback . ())
       (debug . ())))
    (alerts . ())
    (contacts . ())))
EOF
}

create_agentic() {
    cat << 'EOF'
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; AGENTIC.scm - AI agent interaction patterns

(define agentic-config
  `((version . "1.0.0")
    (claude-code
      ((model . "claude-opus-4-5-20251101")
       (tools . ("read" "edit" "bash" "grep" "glob"))
       (permissions . "read-all")))
    (patterns
      ((code-review . "thorough")
       (refactoring . "conservative")
       (testing . "comprehensive")))
    (constraints
      ((languages . ("rescript" "rust" "gleam"))
       (banned . ("typescript" "go" "python" "makefile"))))))
EOF
}

create_neurosym() {
    cat << 'EOF'
;; SPDX-License-Identifier: AGPL-3.0-or-later
;; NEUROSYM.scm - Neurosymbolic integration config

(define neurosym-config
  `((version . "1.0.0")
    (symbolic-layer
      ((type . "scheme")
       (reasoning . "deductive")
       (verification . "formal")))
    (neural-layer
      ((embeddings . false)
       (fine-tuning . false)))
    (integration . ())))
EOF
}

add_if_missing() {
    local repo=$1
    local path=$2
    local content=$3
    local msg=$4

    if ! gh api "repos/$OWNER/$repo/contents/$path" --silent 2>/dev/null; then
        echo "  Adding $path"
        echo "$content" | base64 | tr -d '\n' > /tmp/content.b64
        gh api "repos/$OWNER/$repo/contents/$path" -X PUT \
            -f message="$msg" \
            -f content="$(cat /tmp/content.b64)" \
            --silent 2>/dev/null && echo "    ✓" || echo "    ✗"
    fi
}

echo "Adding SCM files..."
count=0
total=$(wc -l < /tmp/repos-to-configure.txt)

while read repo; do
    ((count++))
    pct=$((count * 100 / total))
    echo "[$count/$total] ($pct%) $repo"
    
    add_if_missing "$repo" "META.scm" "$(create_meta "$repo")" "Add META.scm"
    add_if_missing "$repo" "ECOSYSTEM.scm" "$(create_ecosystem "$repo")" "Add ECOSYSTEM.scm"
    add_if_missing "$repo" "STATE.scm" "$(create_state "$repo")" "Add STATE.scm"
    add_if_missing "$repo" "PLAYBOOK.scm" "$(create_playbook)" "Add PLAYBOOK.scm"
    add_if_missing "$repo" "AGENTIC.scm" "$(create_agentic)" "Add AGENTIC.scm"
    add_if_missing "$repo" "NEUROSYM.scm" "$(create_neurosym)" "Add NEUROSYM.scm"
    
done < /tmp/repos-to-configure.txt

echo "=== SCM files complete ==="
