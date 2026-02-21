# Core Concepts: Two Markers, Two Roles

The _pathroot system uses two complementary markers to provide both location discovery and environment introspection.

## 1. The Global Marker: `_pathroot`

**Location**: `C:\_pathroot` (or drive root on other systems)

**Purpose**: Tells any tool "Here's the root of the devtools universe."

### Characteristics

| Property | Value |
|----------|-------|
| Placement | Drive level (e.g., `C:\`) |
| Scope | System-wide discovery |
| Contents | Path to devtools (e.g., `C:\devtools`) |

### How It Works

```
C:\_pathroot  →  Contains: "C:\devtools"
```

Any script or tool can read this file and instantly know where to find:
- Binaries
- Configurations
- Logs
- Scripts

### Analogy

Think of `_pathroot` as **GPS coordinates**. It tells you *where* you are.

---

## 2. The Local Marker: `_envbase`

**Location**: `C:\devtools\_envbase` (inside the devtools root)

**Purpose**: Describes the environment with structured metadata.

### Characteristics

| Property | Value |
|----------|-------|
| Placement | Inside devtools root |
| Scope | Environment introspection |
| Format | JSON |

### Example Content

```json
{
  "env": "devtools",
  "profile": "default",
  "platform": "windows"
}
```

### Analogy

Think of `_envbase` as the **weather report**. It tells you *what* conditions you're in.

---

## Why Both?

| Marker | Question It Answers |
|--------|---------------------|
| `_pathroot` | "Where are my devtools?" |
| `_envbase` | "What kind of environment is this?" |

### Discovery Flow

```
1. Script starts
2. Reads C:\_pathroot → gets "C:\devtools"
3. Reads C:\devtools\_envbase → gets environment metadata
4. Script now knows WHERE tools are and WHAT context it's in
```

---

## Design Rationale

| Feature | Reason |
|---------|--------|
| Global marker | Enables discovery from any location |
| Local metadata | Keeps environment logic self-contained |
| Declarative format | Easy to inspect, version, and automate |
| File-based | No registry dependencies, portable |

---

## Open Questions

These design decisions are open for discussion:

1. **Registry vs File**: Would you prefer a registry-based marker over a file-based one?
2. **Multiple Profiles**: Should `_envbase` support multiple profiles or overlays?
3. **Cross-Platform**: How should discovery work on WSL, macOS, Linux?
4. **CLI Management**: Would you want a CLI tool to manage these markers interactively?

See [Integration](Integration.md) for how RapidEE can help manage these markers.
