# Integration Lessons & Requirements

> Cross-session learning from `sanctify-php` security tools integration.
> Applies to: `cadre-router`, `cadre-tea-router`, `nafa-app-ambient`

---

## Recipients

| Repo | Maintainer | Action Required |
|------|------------|-----------------|
| `hyperpolymath/cadre-router` | @hyperpolymath | Publish to JSR, ensure Deno-first |
| `hyperpolymath/cadre-tea-router` | @hyperpolymath | Create implementation, publish to JSR |
| `hyperpolymath/nafa-app-ambient` | @hyperpolymath | Consume published packages |

---

## Lessons Learned (from sanctify-php PR #10)

### 1. Pre-built Distribution is Mandatory

**Problem**: GHC unavailability blocked sanctify-php adoption entirely.

**Applies here**: If cadre-router or cadre-tea-router require complex build steps, adoption fails.

**Requirement**:
- Publish to **JSR** (not npm) — Deno-native registry
- Zero build steps for consumers
- `deno add @cadre/router` must just work

### 2. Don't Duplicate Existing Capabilities

**Problem**: php-aegis duplicated WordPress core escaping functions.

**Applies here**: cadre-tea-router should only bridge, not replicate rescript-tea.

**Requirement**:
- cadre-tea-router provides ONLY: `TeaRouter.Make` functor
- Does NOT reimplement: `Tea.Cmd`, `Tea.Sub`, `Tea.Html`
- Thin glue layer, nothing more

### 3. Focus on Unique Value Proposition

**Problem**: Tools found real vulnerabilities only when focused on gaps (Turtle/RDF escaping).

**Applies here**: Type-safe route parsing is the differentiator.

**Requirement**:
- cadre-router: Elm-style parser combinators (`s`, `str`, `</>`, `oneOf`)
- cadre-tea-router: Seamless TEA integration via functor
- Don't try to be a full framework

### 4. Layered Architecture (Defense in Depth)

**Applies here**:
```
rescript-tea (framework) → cadre-tea-router (bridge) → cadre-router (parsing)
```

Each layer has one job. No layer reaches into another's responsibilities.

---

## Enforcement: Deno, Not npm

### MUST NOT Use

| Banned | Reason |
|--------|--------|
| `npm` | Node ecosystem, not Deno-native |
| `package.json` (for deps) | Use `deno.json` imports instead |
| `node_modules/` | Deno caches globally |
| `npx` | Use `deno run` or `deno task` |
| `bun` | Not in allowed toolchain |

### MUST Use

| Required | How |
|----------|-----|
| `deno.json` | Package config, tasks, imports |
| JSR publishing | `deno publish` to `jsr:@cadre/*` |
| `deno add` | Consumers install via Deno |
| `deno task` | Build/dev/test commands |

### Example deno.json (for cadre-router)

```json
{
  "name": "@cadre/router",
  "version": "0.1.0",
  "exports": "./src/client/CadreRouter.js",
  "tasks": {
    "build": "rescript build",
    "test": "deno test --allow-read",
    "publish": "deno publish"
  },
  "imports": {
    "@rescript/core": "npm:@rescript/core@^1.0.0"
  }
}
```

### Example Consumer Usage (nafa-app-ambient)

```json
{
  "imports": {
    "@cadre/router": "jsr:@cadre/router@^0.1",
    "@cadre/tea-router": "jsr:@cadre/tea-router@^0.1"
  }
}
```

---

## Priority Matrix: cadre-router

### MUST (Blockers)

| Task | Why |
|------|-----|
| Merge `claude/type-safe-routing-SPtP7` to main | Unblock consumers |
| Publish to JSR as `@cadre/router` | Zero-friction install |
| Export `Parser`, `Navigation`, `Url`, `Link` | Core API surface |
| Add `deno.json` with proper exports | Deno-native config |
| SPDX headers on all files | License compliance |

### SHOULD (Important)

| Task | Why |
|------|-----|
| Add README with usage examples | Adoption |
| Add basic test suite | Confidence |
| Document Parser combinator API | Discoverability |
| Ensure ReScript 11+ compatibility | Modern toolchain |

### COULD (Nice to Have)

| Task | Why |
|------|-----|
| Hash-based routing variant | Some SPAs need it |
| Query parameter helpers | Convenience |
| TypeScript type declarations | Wider reach |

---

## Priority Matrix: cadre-tea-router

### MUST (Blockers)

| Task | Why |
|------|-----|
| Create repo with implementation | Doesn't exist yet |
| Implement `TeaRouter.Make` functor | Core functionality |
| Publish to JSR as `@cadre/tea-router` | Zero-friction install |
| Depend on `@cadre/router` via JSR | Clean dependency |
| SPDX headers on all files | License compliance |

### SHOULD (Important)

| Task | Why |
|------|-----|
| Add example TEA app | Demonstrates usage |
| Test with rescript-tea | Verify integration |
| Document functor config | Adoption |

### COULD (Nice to Have)

| Task | Why |
|------|-----|
| Hash navigation support | Some apps need it |
| SSR helpers | Server rendering |

---

## Priority Matrix: nafa-app-ambient

### MUST (Blockers)

| Task | Why |
|------|-----|
| Wait for cadre-router on JSR | Dependency |
| Wait for cadre-tea-router on JSR | Dependency |
| Create monorepo structure | Foundation |

### SHOULD (After Dependencies Ready)

| Task | Why |
|------|-----|
| Port shared types (Domain, Route, Api) | Type safety |
| Implement Router.res with functor | Core routing |
| Port page modules | UI |
| Remove Elm code | Cleanup |

### COULD (Future)

| Task | Why |
|------|-----|
| Server-side cadre-router | Stage 3 |
| CRDT state integration | Real-time features |

---

## Verification Checklist

Before considering integration complete:

- [ ] `deno add @cadre/router` works from fresh project
- [ ] `deno add @cadre/tea-router` works from fresh project
- [ ] No `node_modules/` anywhere in consumer project
- [ ] No `package.json` required for runtime deps
- [ ] `deno task dev` starts nafa-app-ambient
- [ ] Route changes work (back/forward, links, programmatic)
- [ ] Type errors on invalid routes at compile time

---

## Contact

Questions about this integration:
- Repo issues on respective GitHub repos
- Tag @hyperpolymath for coordination
