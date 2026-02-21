# CarecTL Profiles

<!-- SPDX-License-Identifier: MIT OR AGPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2025 hyperpolymath -->

Audit-grade compliance profiles for nano-aider workflows.

## Profiles

| Profile | Purpose | Failure Mode |
|---------|---------|--------------|
| `onboarding.yaml` | Entry-level contributor checks | `warn` |
| `strict.yaml` | Pre-commit enforcement | `deny` |
| `teardown.yaml` | Post-merge cleanup verification | `deny` |
| `discovery-assist.yaml` | Reproducible option discovery flow | `warn` |

## Reproducible Assist Flow: Discovery

The `discovery-assist` profile provides a **reproducible workflow** for
discovering hidden nano/micro editor options.

### Usage

```bash
# Run the discovery assist flow
carectl run --profile discovery-assist

# Or manually execute the steps
nano-aider --list --format=json > discovered_options.json
```

### Flow Steps

```
┌─────────────────────┐
│ 1. detect_editor    │  Verify nano/micro is installed
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 2. check_version    │  Ensure version >= 5.0
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 3. locate_config    │  Find ~/.nanorc or XDG config
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 4. scan_hidden      │  Run nano-aider discovery
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 5. diff_current     │  Compare against existing config
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│ 6. generate_report  │  Output discovery_report.md
└─────────────────────┘
```

### Outputs

After running the discovery assist flow:

- `discovered_options.json` - All hidden options found
- `missing_options.json` - Options not in your current config
- `discovery_report.md` - Human-readable summary

### Reproducibility Guarantee

This flow is **idempotent** and **deterministic**:

- Same editor version → Same discovered options
- No network calls required
- No side effects to system configuration
- Output artifacts are versioned and diffable

### Integration with CI

```yaml
# .github/workflows/discovery.yml
- name: Run discovery assist
  run: carectl run --profile discovery-assist

- name: Upload artifacts
  uses: actions/upload-artifact@v4
  with:
    name: discovery-report
    path: |
      discovered_options.json
      discovery_report.md
```

## Lock Scope Compliance

All profiles respect [LOCK_SCOPE.md](../LOCK_SCOPE.md):

- ✅ No network access required
- ✅ No root privileges needed
- ✅ Read-only filesystem operations
- ✅ No arbitrary code execution
- ✅ Deterministic outputs
