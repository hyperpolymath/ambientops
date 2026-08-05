<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# REQUIRES INITIALISATION

**This repository is not finished being set up.** 28 substitution token(s) across 40 file(s) still have no value.

## Why this is not already done

This repo was created from `hyperpolymath/rsr-template-repo`. The mint
(`just repo-init`) fills every token that has a single mechanical answer —
owner, repo, author, dates, licence, branch — and it has done so here.

The tokens below are the ones it *deliberately cannot* answer. They need a
decision or a fact that exists only in your head: what this project is for,
what command builds it, which port the service listens on, whether a PGP key
is held at all. The template's own token vocabulary says as much — you cannot
sensibly answer "required invariants" in a thirty-second bootstrap.

They were left **visibly unfilled on purpose**. The alternatives were both
worse: inventing plausible values would put confident falsehoods into a
security policy and an architecture document, and silently deleting the
sections would hide the fact that a decision is owed. A visible gap is
honest; a fabricated answer is not.

## Do not delete this file until every item below is resolved

This file is the only marker that the work is outstanding. Deleting it early
does not finish the setup, it just conceals it — and the next person or agent
to arrive will reasonably assume the repo is complete.

- **If you are a person:** delete this file yourself once the last item is done.
- **If you are an agent:** resolve what you legitimately can, leave the rest,
  and delete this file only when no token below remains anywhere in the tree.
  Do not delete it to make a gate go green.

Re-running the estate top-up tool will remove this file automatically once
nothing is outstanding, so the safest way to finish is to fix the tokens and
let the check confirm it.

## What is needed, and where it goes

### `{{ALGO}}`

Appears in:

- `cicada/Justfile`

### `{{APP}}`

Appears in:

- `monitoring/systems-observatory/Justfile`

### `{{ARGS}}`

Arguments for the justfile recipe this appears in.

Appears in:

- `Justfile`
- `panoptes/Justfile`
- `recovery/operating-theatre/tasks/Justfile`

### `{{BACKUP_PATH}}`

Appears in:

- `cicada/Justfile`

### `{{COMMAND}}`

Appears in:

- `cicada/Justfile`

### `{{CONDUCT_TEAM}}`

Name of the conduct body. If there is no committee, rewrite the sentence rather than substituting a plural noun into 'a {{CONDUCT_TEAM}} member'.

Appears in:

- `_pathroot/CODE_OF_CONDUCT.md`
- `ambulances/disk/CODE_OF_CONDUCT.md`
- `ambulances/performance/CODE_OF_CONDUCT.md`
- `ambulances/security/CODE_OF_CONDUCT.md`
- `contracts/CODE_OF_CONDUCT.md`
- `emergency-button/CODE_OF_CONDUCT.md`
- `hardware-crash-team/CODE_OF_CONDUCT.md`
- `monitoring/flare/CODE_OF_CONDUCT.md`
- `monitoring/observatory/CODE_OF_CONDUCT.md`
- `nerdsafe-restart/CODE_OF_CONDUCT.md`
- `playbooks/CODE_OF_CONDUCT.md`
- `project-cb/CODE_OF_CONDUCT.md`
- `recovery/emergency-room/CODE_OF_CONDUCT.md`
- `recovery/freeze-ejector/CODE_OF_CONDUCT.md`
- `slopctl/CODE_OF_CONDUCT.md`
- `total-recall/CODE_OF_CONDUCT.md`

### `{{CREATED_DATE}}`

Appears in:

- `_pathroot/.well-known/provenance.json`

### `{{DAYS}}`

Appears in:

- `cicada/Justfile`

### `{{EXPIRY_DATE}}`

Appears in:

- `_pathroot/.well-known/security.txt`

### `{{FILE}}`

Appears in:

- `broad-spectrum/Justfile`
- `cicada/Justfile`
- `monitoring/systems-observatory/Justfile`

### `{{GITHUB_KEY_ID}}`

Appears in:

- `cicada/Justfile`

### `{{KEY_ID}}`

Appears in:

- `cicada/Justfile`

### `{{LAST_UPDATE}}`

Appears in:

- `_pathroot/.well-known/humans.txt`

### `{{MESSAGE}}`

Appears in:

- `recovery/operating-theatre/tasks/Justfile`

### `{{N}}`

Appears in:

- `cicada/Justfile`

### `{{OUTPUT}}`

Appears in:

- `broad-spectrum/Justfile`
- `monitoring/systems-observatory/Justfile`

### `{{PGP_KEY_URL}}`

Public URL the PGP key can be fetched from. Same caveat as PGP_FINGERPRINT.

Appears in:

- `_pathroot/SECURITY.md`
- `ambulances/disk/SECURITY.md`
- `ambulances/performance/SECURITY.md`
- `ambulances/security/SECURITY.md`
- `contracts/SECURITY.md`
- `emergency-button/SECURITY.md`
- `monitoring/observatory/SECURITY.md`
- `nerdsafe-restart/SECURITY.md`
- `recovery/emergency-room/SECURITY.md`
- `total-recall/SECURITY.md`

### `{{PLAN_ID}}`

Appears in:

- `recovery/operating-theatre/tasks/Justfile`

### `{{PROJECT_UNIQUE_STRENGTH}}`

What this does that its alternatives do not.

Appears in:

- `.machine_readable/agent_instructions/methodology.a2ml`

### `{{RECEIPT_ID}}`

Appears in:

- `recovery/operating-theatre/tasks/Justfile`

### `{{RECIPE}}`

Appears in:

- `hybrid-automation-router/Justfile`

### `{{RESPONSE_TIME}}`

Initial-response SLA for a security or conduct report. Promise only what a solo maintainer can actually meet.

Appears in:

- `_pathroot/CODE_OF_CONDUCT.md`
- `ambulances/disk/CODE_OF_CONDUCT.md`
- `ambulances/performance/CODE_OF_CONDUCT.md`
- `ambulances/security/CODE_OF_CONDUCT.md`
- `contracts/CODE_OF_CONDUCT.md`
- `emergency-button/CODE_OF_CONDUCT.md`
- `hardware-crash-team/CODE_OF_CONDUCT.md`
- `monitoring/flare/CODE_OF_CONDUCT.md`
- `monitoring/observatory/CODE_OF_CONDUCT.md`
- `nerdsafe-restart/CODE_OF_CONDUCT.md`
- `playbooks/CODE_OF_CONDUCT.md`
- `project-cb/CODE_OF_CONDUCT.md`
- `recovery/emergency-room/CODE_OF_CONDUCT.md`
- `recovery/freeze-ejector/CODE_OF_CONDUCT.md`
- `slopctl/CODE_OF_CONDUCT.md`
- `total-recall/CODE_OF_CONDUCT.md`

### `{{STRATEGY}}`

Appears in:

- `monitoring/systems-observatory/Justfile`

### `{{TITLE}}`

Appears in:

- `cicada/Justfile`

### `{{UPDATED_DATE}}`

Appears in:

- `_pathroot/.well-known/provenance.json`

### `{{URL}}`

Appears in:

- `broad-spectrum/Justfile`

### `{{VERSION}}`

Version/tag for the container image.

Appears in:

- `_pathroot/.well-known/provenance.json`
- `cicada/Justfile`
- `immutable-linux-auditor/Justfile`
- `monitoring/systems-observatory/Justfile`
- `network-dashboard/Justfile`
- `personal-sysadmin/scripts/github-admin/add-justfile-mustfile.sh`
- `recovery/operating-theatre/tasks/Justfile`

### `{{WEBSITE}}`

Project homepage URL, or delete the field if there is none.

Appears in:

- `_pathroot/SECURITY.md`
- `ambulances/disk/SECURITY.md`
- `ambulances/performance/SECURITY.md`
- `ambulances/security/SECURITY.md`
- `contracts/SECURITY.md`
- `emergency-button/SECURITY.md`
- `monitoring/observatory/SECURITY.md`
- `nerdsafe-restart/SECURITY.md`
- `recovery/emergency-room/SECURITY.md`
- `total-recall/SECURITY.md`

---

Generated by the estate top-up pass. Rationale and the governing rulings are
in `hyperpolymath/standards`; the token vocabulary is
`.machine_readable/ai/PLACEHOLDERS.adoc` in `rsr-template-repo`.
