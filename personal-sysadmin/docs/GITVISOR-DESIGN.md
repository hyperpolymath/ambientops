# git-hud: Neurosymbolic CI/CD Intelligence System

## Core Philosophy

**"Dumb rules from smart learning"** - The system learns complex patterns through neural analysis, then distills them into simple, fast-acting declarative rules that can be:
- Pre-emptively injected into new repos
- Applied as cures to existing repos
- Executed without ML inference overhead

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        git-hud                                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                 LEARNING LAYER (Neural)                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │   │
│  │  │ Pattern     │  │ Anomaly     │  │ Optimization    │   │   │
│  │  │ Recognition │  │ Detection   │  │ Suggestions     │   │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │   │
│  │                         │                                 │   │
│  │                         ▼                                 │   │
│  │  ┌─────────────────────────────────────────────────────┐ │   │
│  │  │              RULE DISTILLATION                       │ │   │
│  │  │  Neural insights → Logtalk predicates → Fast rules   │ │   │
│  │  └─────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              SYMBOLIC LAYER (Logtalk + Prolog)            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │   │
│  │  │ Declarative │  │ Imperative  │  │ Inference       │   │   │
│  │  │ Rules       │  │ Procedures  │  │ Engine          │   │   │
│  │  │ (what)      │  │ (how)       │  │ (why)           │   │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    DATA LAYER                             │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │   │
│  │  │ ArangoDB    │  │ Dragonfly   │  │ Radicle         │   │   │
│  │  │ (Graph)     │  │ (Cache)     │  │ (P2P Git)       │   │   │
│  │  │ - Repos     │  │ - Rules     │  │ - Decentralized │   │   │
│  │  │ - Patterns  │  │ - Results   │  │ - Federation    │   │   │
│  │  │ - History   │  │ - Locks     │  │ - Replication   │   │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   ACTION LAYER                            │   │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────┐ │   │
│  │  │ Preventive │ │ Curative   │ │ Diagnostic │ │ Hooks  │ │   │
│  │  │ Injection  │ │ Repair     │ │ Reports    │ │ System │ │   │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────┘ │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  FORGE ADAPTERS                           │   │
│  │  GitHub │ GitLab │ Bitbucket │ Codeberg │ sr.ht │ Gitea  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Logtalk Rule System

### Rule Categories

```logtalk
:- object(cicd_rules).

    % DECLARATIVE RULES (what should be true)
    :- public(repo_must_have/2).
    repo_must_have(Repo, 'dependabot.yml') :-
        repo_uses_dependencies(Repo).
    repo_must_have(Repo, 'codeql.yml') :-
        repo_has_code(Repo).
    repo_must_have(Repo, 'SECURITY.md') :-
        repo_is_public(Repo).

    % IMPERATIVE PROCEDURES (how to fix)
    :- public(fix_missing_file/3).
    fix_missing_file(Repo, File, Template) :-
        \+ repo_has_file(Repo, File),
        get_template(File, Template),
        inject_file(Repo, File, Template).

    % PREVENTIVE RULES (stop before it happens)
    :- public(block_commit_if/2).
    block_commit_if(Commit, 'typescript_detected') :-
        commit_adds_file(Commit, File),
        file_extension(File, '.ts').
    block_commit_if(Commit, 'secret_detected') :-
        commit_content_matches(Commit, secret_pattern(_)).

    % CURATIVE RULES (fix after detection)
    :- public(auto_fix/2).
    auto_fix(Repo, unpinned_actions) :-
        find_unpinned_actions(Repo, Actions),
        pin_actions_to_sha(Repo, Actions).
    auto_fix(Repo, missing_permissions) :-
        find_workflows_without_permissions(Repo, Workflows),
        add_permissions(Repo, Workflows, 'read-all').

:- end_object.
```

### Pattern Learning → Rule Generation

```logtalk
:- object(rule_distiller).

    % Learn from failure patterns
    :- public(distill_rule/2).
    distill_rule(Pattern, Rule) :-
        % Neural layer detected pattern
        neural_pattern(Pattern, Confidence),
        Confidence > 0.85,
        % Convert to symbolic rule
        pattern_to_predicate(Pattern, Predicate),
        % Validate against existing rules
        \+ conflicting_rule(Predicate),
        % Generate fast-path rule
        compile_rule(Predicate, Rule).

    % Example: Learning that repos with Rust + no fuzz = security issues
    pattern_to_predicate(
        pattern(rust_no_fuzz, [has_rust, no_fuzzing], security_risk),
        (repo_needs_fuzzing(R) :- repo_language(R, rust), \+ repo_has_fuzzing(R))
    ).

:- end_object.
```

## ArangoDB Schema

### Collections

```javascript
// repos - Repository metadata
{
  "_key": "github/hyperpolymath/bunsenite",
  "forge": "github",
  "owner": "hyperpolymath",
  "name": "bunsenite",
  "languages": ["rust", "nickel"],
  "health_score": 85,
  "last_scan": "2025-12-29T00:00:00Z",
  "issues": ["mirror_failing", "fuzzing_incomplete"],
  "rules_applied": ["r001", "r042", "r103"]
}

// rules - Distilled rules
{
  "_key": "r001",
  "name": "require_dependabot",
  "type": "preventive",
  "priority": "high",
  "logtalk": "repo_must_have(R, 'dependabot.yml') :- repo_uses_dependencies(R).",
  "origin": "neural_distillation",
  "confidence": 0.97,
  "applied_count": 15420,
  "success_rate": 0.99
}

// patterns - Learned patterns
{
  "_key": "p_mirror_ssh_fail",
  "description": "Mirror fails when SSH key missing",
  "detection": "workflow_name='mirror' AND conclusion='failure' AND log_contains='Permission denied'",
  "frequency": 2341,
  "distilled_rules": ["r087", "r088"]
}

// fixes - Applied fixes history
{
  "_key": "fix_20251229_001",
  "repo": "github/hyperpolymath/bunsenite",
  "rule": "r001",
  "action": "inject_file",
  "file": ".github/dependabot.yml",
  "timestamp": "2025-12-29T00:00:00Z",
  "result": "success"
}
```

### Graph Edges

```javascript
// repo_depends_on - Dependency relationships
{ "_from": "repos/bunsenite", "_to": "repos/januskey", "type": "uses" }

// rule_fixes - What rules fix what issues
{ "_from": "rules/r001", "_to": "patterns/p_no_dependabot", "confidence": 0.98 }

// derived_from - Rule derivation chain
{ "_from": "rules/r042", "_to": "rules/r001", "type": "specialization" }
```

## Dragonfly Caching Strategy

```yaml
# Fast-path rule cache
rules:
  key_pattern: "rule:{rule_id}"
  ttl: 3600  # 1 hour
  data: compiled_logtalk_bytecode

# Repo state cache
repos:
  key_pattern: "repo:{forge}:{owner}:{name}"
  ttl: 300   # 5 minutes
  data: { health_score, issues, last_check }

# Lock for concurrent operations
locks:
  key_pattern: "lock:{repo}:{operation}"
  ttl: 60    # 1 minute max

# Result memoization
results:
  key_pattern: "result:{rule}:{repo}:{hash}"
  ttl: 86400 # 24 hours
```

## Hook System

### Pre-commit Hooks (Preventive)

```bash
#!/bin/bash
# .git/hooks/pre-commit (injected by git-hud)

# Fast local checks (cached rules)
git-hud check --local --cached

# Checks:
# - No banned languages (TS, Go, Python, Makefile)
# - No secrets in staged files
# - Formatting compliance
# - License headers present
```

### Pre-push Hooks (Validation)

```bash
#!/bin/bash
# .git/hooks/pre-push

# Validate against git-hud rules
git-hud validate --pre-push

# Checks:
# - All commits signed
# - CI will pass (local simulation)
# - No breaking changes to public API
```

### Post-receive Hooks (Curative)

```bash
#!/bin/bash
# Server-side hook

# Trigger git-hud scan
git-hud scan --repo $REPO --event push

# Auto-fix if configured
git-hud fix --auto --repo $REPO
```

## Self-Improving Diagnostics

### Diagnostic Pipeline

```
1. DETECT
   └─ Continuous monitoring of all forges
   └─ Webhook listeners for real-time events
   └─ Scheduled deep scans

2. ANALYZE
   └─ Neural pattern matching
   └─ Symbolic rule evaluation
   └─ Graph traversal for dependencies

3. DIAGNOSE
   └─ Root cause identification
   └─ Impact assessment
   └─ Fix recommendations

4. REPAIR
   └─ Auto-fix if confidence > 95%
   └─ Propose PR if confidence 80-95%
   └─ Alert human if confidence < 80%

5. LEARN
   └─ Track fix success/failure
   └─ Update pattern weights
   └─ Distill new rules
   └─ Prune ineffective rules
```

### Diagnostic Report Format

```yaml
# .git-hud/diagnostic.yml
scan_date: 2025-12-29T00:00:00Z
repo: hyperpolymath/bunsenite
health_score: 85

issues:
  - id: ISS-001
    severity: high
    category: security
    description: "Mirror workflow failing due to missing SSH keys"
    rule: r087
    auto_fixable: false
    recommendation: "Configure GITLAB_SSH_KEY org secret"

  - id: ISS-002
    severity: medium
    category: quality
    description: "GitHub Actions not pinned to SHA"
    rule: r042
    auto_fixable: true
    fix_pr: "#123"

applied_fixes:
  - rule: r001
    file: .github/dependabot.yml
    status: success

learnings:
  - pattern: "rust_repos_need_clippy"
    confidence: 0.89
    pending_distillation: true
```

## New Repo Bootstrap

When a new repo is created, git-hud automatically:

```logtalk
:- object(repo_bootstrap).

    :- public(initialize/1).
    initialize(Repo) :-
        % Detect repo characteristics
        detect_languages(Repo, Languages),
        detect_frameworks(Repo, Frameworks),

        % Apply preventive rules
        findall(Rule, applicable_preventive_rule(Repo, Rule), Rules),
        apply_rules(Repo, Rules),

        % Inject hooks
        inject_hooks(Repo, [pre_commit, pre_push]),

        % Set up monitoring
        register_webhooks(Repo),
        schedule_scans(Repo, daily),

        % Initial diagnostic
        run_diagnostic(Repo, Report),
        store_baseline(Repo, Report).

:- end_object.
```

### Files Injected on New Repo

```
.github/
├── dependabot.yml          # Dependency updates
├── FUNDING.yml             # Sponsorship
├── CODEOWNERS              # Review routing
├── workflows/
│   ├── codeql.yml          # Security scanning
│   ├── scorecard.yml       # OSSF compliance
│   ├── rsr-policy.yml      # Language policy
│   └── git-hud-check.yml  # git-hud integration
│
.git-hud/
├── config.yml              # git-hud settings
├── rules.pl                # Local rule overrides
└── diagnostic.yml          # Latest scan results
│
SECURITY.md                 # Security policy
CONTRIBUTING.adoc           # Contribution guide
CODE_OF_CONDUCT.md          # Community standards
justfile                    # Task runner
Mustfile                    # Mandatory checks
META.scm                    # Architecture decisions
ECOSYSTEM.scm               # Ecosystem position
STATE.scm                   # Project state
```

## K8s Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: git-hud
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: git-hud-core
          image: hyperpolymath/git-hud:latest
          resources:
            requests:
              memory: "2Gi"
              cpu: "1"
          env:
            - name: ARANGO_URL
              value: "http://arangodb:8529"
            - name: DRAGONFLY_URL
              value: "redis://dragonfly:6379"

        - name: logtalk-engine
          image: hyperpolymath/git-hud-logtalk:latest
          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"

        - name: neural-worker
          image: hyperpolymath/git-hud-neural:latest
          resources:
            requests:
              memory: "4Gi"
              cpu: "2"
              nvidia.com/gpu: 1  # For inference
---
apiVersion: v1
kind: Service
metadata:
  name: git-hud-api
spec:
  type: LoadBalancer
  ports:
    - port: 8080
      targetPort: 8080
```

## API Endpoints

```
POST /api/v1/repos/{forge}/{owner}/{name}/scan
POST /api/v1/repos/{forge}/{owner}/{name}/fix
GET  /api/v1/repos/{forge}/{owner}/{name}/diagnostic
GET  /api/v1/repos/{forge}/{owner}/{name}/health

POST /api/v1/rules/distill
GET  /api/v1/rules
GET  /api/v1/rules/{id}
PUT  /api/v1/rules/{id}/enable
DELETE /api/v1/rules/{id}

GET  /api/v1/patterns
GET  /api/v1/patterns/{id}/rules

POST /api/v1/hooks/github
POST /api/v1/hooks/gitlab
POST /api/v1/hooks/bitbucket
```

## Implementation Phases

### Phase 1: Foundation
- [ ] ArangoDB schema setup
- [ ] Dragonfly caching layer
- [ ] Basic Logtalk rule engine
- [ ] GitHub adapter

### Phase 2: Intelligence
- [ ] Neural pattern detection
- [ ] Rule distillation pipeline
- [ ] Self-improving diagnostics
- [ ] Auto-fix engine

### Phase 3: Scale
- [ ] Multi-forge support (GitLab, Bitbucket, Codeberg)
- [ ] Radicle P2P integration
- [ ] K8s orchestration
- [ ] git-private-farm integration

### Phase 4: Ecosystem
- [ ] Cross-org federation
- [ ] Public rule marketplace
- [ ] Community pattern sharing
- [ ] Enterprise features
