<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Comment Bank Project - Ideas

## Current Tools

### Comment Collector (`comment-collector.html`)
- Four zones: Framework, Margin, In-Text, Summary
- Drag and drop from any app
- Inline editing with error highlighting
- **Tag system**: Content, Overall Structure, Detailed Structure, Evidencing, Conventions
- Filter by tag per zone
- Session buffer (explicit save, discard, undo)
- Export to SCM format

### Text X-Ray (`text-xray.html`)
- Paste/drop text for instant analysis
- **No AI/LLM** - purely rule-based, safe for live assignments
- Basic stats: words, sentences, paragraphs, avg lengths
- Readability: Flesch Reading Ease, Flesch-Kincaid Grade, Gunning Fog, SMOG
- Style: passive voice, hedging, fillers, sentence length distribution
- Formality score: contractions, first-person, exclamations
- Logic markers: transitions by type (addition, contrast, cause, sequence, example, conclusion)

---

## Future Ideas

### 1. LibreOffice Extension (.oxt)

**Why:** Dock inside LO, insert comments directly into documents.

**Approach:**
- Python-UNO scripting
- Sidebar panel or floating dialog
- Hook into text selection events
- Two-way: collect from selection, insert from bank

**Files needed:**
```
extension/
├── META-INF/manifest.xml
├── description.xml
├── Addons.xcu
├── python/
│   └── comment_collector.py
└── dialog/
    └── CollectorDialog.xdl
```

### 2. Word/Office Add-in

**Why:** Same functionality for Word users.

**Approach:**
- Office.js task pane add-in
- Can reuse existing HTML/JS with minor changes
- Manifest.xml for deployment
- Works in Word Online too

### 3. Desktop App (Tauri)

**Why:** Native floating window, always-on-top, global hotkeys.

**Approach:**
- Tauri 2.0 + existing HTML/JS frontend
- Rust backend for file I/O
- System tray icon
- Global hotkey to show/hide
- Drag from any app

### 4. VS Code Extension

**Why:** For tutors who mark in VS Code / code-based assignments.

**Approach:**
- Webview panel with existing HTML
- Commands for inserting comments
- Workspace storage for banks

### 5. Improved Error Detection

- Hunspell integration for real spell checking
- LanguageTool API for grammar
- Custom dictionary per module
- Learn from corrections

### 6. Comment Bank Sync

- Sync banks between devices
- Import/merge from colleagues
- Version history
- Cloud storage (optional, privacy-first)

### 7. Statistics & Analytics

- Most-used comments
- Time spent per category
- Marking session tracking
- Export reports

### 8. Layered Protection System (Inner/Outer Keep)

**Problem:** Risk of accidentally destroying your entire comment bank

**Solution:** Three-tier protection with backup history

**Layers (inner to outer):**

```
┌─────────────────────────────────────────┐
│         PERSONAL (fully editable)       │ ← Your working comments
├─────────────────────────────────────────┤
│       COMMUNITY (import/export only)    │ ← Curated best practice
├─────────────────────────────────────────┤
│        INSTITUTIONAL (read-only)        │ ← OU-provided core
└─────────────────────────────────────────┘
```

**Inner Keep (Protected):**
- OU-provided standard comments (immutable in-app)
- Community-curated/approved comments
- Can only be modified outside the tool (file editing)
- Versioned with clear provenance

**Outer Keep (Working):**
- Personal comments, refinements, experiments
- Full edit/delete capability
- Over time, refined ones can be promoted to community layer

**Backup History:**
1. **Session buffer** - unsaved changes, discard by not saving
2. **Current** - active saved state
3. **Previous** - one step back (auto-snapshot before save)
4. **Archive** - periodic snapshots (daily/weekly)

**Implementation:**
```
~/.comment-bank/
├── institutional/      # Read-only, from package
│   └── ou-standard.scm
├── community/          # Import-only
│   └── curated-2024.scm
├── personal/           # Full access
│   ├── current.scm
│   ├── previous.scm    # Auto-backup
│   └── archive/
│       ├── 2024-01-15.scm
│       └── 2024-01-08.scm
└── session.scm         # Unsaved working copy
```

### 9. Import/Export Formats

- AceText .atc (done - import-acetext.py)
- Plain text (one comment per line)
- CSV (category, text, tags)
- JSON (for web interop)
- Markdown (for documentation)

### 10. MiniKanren Comment Quality Learning

**Goal:** Rule-based learning system that can assess comment quality without LLM

**Why MiniKanren:**
- Logic programming for declarative rules
- Can infer new rules from examples
- Explainable reasoning (not a black box)
- Safe for live assignments (no AI/LLM)

**Approach:**
1. Define quality relations as logical predicates
2. Train on existing comment bank (with your consent)
3. Infer quality patterns from good/bad examples
4. Generate explainable quality scores

**Quality Dimensions to Learn:**
- Clarity (sentence structure, word choice)
- Specificity (concrete vs vague feedback)
- Actionability (does it tell student what to do?)
- Tone (encouraging vs discouraging)
- Completeness (addresses the issue fully?)

**Training Data:**
- Your comment bank (815+ AceText clips)
- Categorised by effectiveness
- Note: Your style is for monitors, not students

**Implementation Options:**
- Guile Scheme with miniKanren
- Racket with miniKanren
- Core.logic (Clojure)
- OCanren (OCaml)

**Output:**
- Quality score per comment
- Suggested improvements (rule-based)
- Pattern matching for similar good comments
- Learnable rules that improve over time

---

## Related Projects

### tma-mark2 Repository
This comment bank project integrates with the tma-mark2 system, which modernises two legacy OU tools:

[cols="1,2,2"]
|===
|Tool |Original |Purpose

|eTMA Handler
|Swing/Java
|For *tutors* marking student submissions

|eTMA Monitor
|Swing/Java
|For *monitors* checking tutor marking quality
|===

*Together*: Handler + Monitor + Comment Bank = effective marking workflow

The modernised versions share comment banks and feedback templates.

---

## Technical Notes

### SCM Format (machine)
See `comment-bank.scm` - S-expressions for programmatic access.

### Djot Format (human)
See `comment-bank.djot` - readable reference with IDs in attributes.

### Storage
Currently: browser localStorage
Future: SQLite or file-based for portability

---

Last updated: 2026-01-05
