# ETHICS.md - GDPR, Privacy, and Educational Context

This document explains the ethical framework, GDPR compliance implementation, and educational value of Juisys.

---

## Table of Contents

1. [Core Privacy Principles](#core-privacy-principles)
2. [GDPR Compliance](#gdpr-compliance)
3. [Hazard Triangle Methodology](#hazard-triangle-methodology)
4. [Calm Technology Principles](#calm-technology-principles)
5. [Educational Framework](#educational-framework)
6. [Attribution and Development Context](#attribution-and-development-context)
7. [Ethical Use](#ethical-use)

---

## Core Privacy Principles

Juisys is built on four foundational privacy principles:

### 1. Local Processing Only (Article 5.1.f)

**Implementation**: Zero network calls in entire codebase.

**Why**:
- Eliminates data breach risk via network interception
- No dependency on external services
- Complete user control over data flow
- Demonstrates integrity and confidentiality principle

**Verification**: Run self-audit (Mode 6) to scan source code for network functions.

### 2. Ephemeral Data (Article 5.1.e)

**Implementation**: All data stored in memory only, cleared when Julia process ends.

**Why**:
- Storage limitation principle
- Minimizes data retention risks
- No persistent tracking of user behavior
- Forces intentional data retention (via export with consent)

**Trade-off**: No history tracking, but privacy worth it.

### 3. Explicit Consent (Article 6.1.a)

**Implementation**: `Security.request_consent()` before any system access.

**Why**:
- Lawful basis for processing
- User autonomy and control
- Granular permissions (separate for scan, file write, IoT, etc.)
- Revocable at any time

**Example**:
```julia
if !Security.has_consent(Security.SYSTEM_SCAN)
    granted = Security.request_consent(
        Security.SYSTEM_SCAN,
        "To audit installed software for privacy/cost analysis"
    )
    if !granted
        # Fall back to NO PEEK mode
        return
    end
end
```

### 4. Transparency (Article 5.1.a)

**Implementation**: Self-auditing capability, open source code.

**Why**:
- Users can verify privacy claims
- Educational value - show how it's done
- Accountability through code inspection
- Demonstrates fairness principle

---

## GDPR Compliance

Juisys implements all 12 processing types defined in GDPR Article 4(2).

### The 12 Processing Types

#### 1. Collection
**Where**: `IO.manual_entry()`, `IO.import_from_file()`, `Automate.scan_installed_apps()`

**How**: User provides data manually, from files, or via system scan (with consent)

**Privacy**: Minimal collection - app names and metadata only, no PII

#### 2. Recording
**Where**: `Security.ConsentRecord` struct, temporary variables

**How**: Store in memory during session

**Privacy**: Ephemeral only, cleared on exit

#### 3. Organization
**Where**: `Core.classify_app()`, category assignment

**How**: Group apps by category, risk level

**Privacy**: Local processing, no external categorization APIs

#### 4. Structuring
**Where**: `Core.App` struct, `Core.ClassificationResult`

**How**: Defined data structures with clear schemas

**Privacy**: Minimal required fields

#### 5. Storage
**Where**: In-memory vectors and dicts

**How**: Session-scoped only

**Privacy**: NO persistent storage of personal data

#### 6. Adaptation/Alteration
**Where**: `Core.calculate_privacy_score()`, `Core.assess_risk()`

**How**: Transform raw data into scores and classifications

**Privacy**: Deterministic algorithms, no ML profiling

#### 7. Retrieval
**Where**: `Core.match_alternatives()`, database lookups

**How**: Query local JSON database

**Privacy**: No external database queries

#### 8. Consultation
**Where**: `CLI.run()`, `GUI.launch()`, user queries

**How**: Display results to user

**Privacy**: Terminal/local GUI only

#### 9. Use
**Where**: Analysis, report generation

**How**: Process data for audit purposes only

**Privacy**: Purpose limitation - only for auditing

#### 10. Disclosure by Transmission
**Where**: `Reports.generate_report()` (requires consent)

**How**: Write to local file only with FILE_WRITE consent

**Privacy**: User explicitly chooses to persist data

#### 11. Dissemination/Making Available
**Where**: Optional report exports

**How**: User decides what, where, when to export

**Privacy**: User controls dissemination

#### 12. Erasure/Destruction
**Where**: `Security.clear_all_consent()`, `Core.cleanup_session_data()`

**How**: Automatic on session end

**Privacy**: Right to be forgotten enforced by design

### GDPR Articles Directly Implemented

| Article | Principle | Implementation |
|---------|-----------|----------------|
| **5.1.a** | Lawfulness, Fairness, Transparency | Consent framework, self-audit, open source |
| **5.1.b** | Purpose Limitation | Data used only for auditing apps, not profiling users |
| **5.1.c** | Data Minimization | Collect app names only, no unnecessary data |
| **5.1.d** | Accuracy | User reviews and confirms data before processing |
| **5.1.e** | Storage Limitation | Ephemeral data, automatic erasure |
| **5.1.f** | Integrity & Confidentiality | No network calls, local processing |
| **6.1.a** | Consent as lawful basis | `Security.request_consent()` |
| **7.3** | Right to withdraw consent | `Security.revoke_consent()` |
| **15** | Right of access | User sees all collected data in UI |
| **17** | Right to erasure | Automatic + manual cleanup functions |
| **25** | Data protection by design | Privacy-first architecture |

---

## Hazard Triangle Methodology

Adapted from OSHA's Hierarchy of Controls for privacy/security:

### Level 1: ELIMINATE (Most Effective)

**NO PEEK Mode** - Eliminate system access entirely.

**How**: Manual entry only, zero system permissions needed.

**When to use**:
- Sensitive environments
- Untrusted systems
- Learning/testing
- Maximum privacy requirement

**Trade-off**: Manual effort, but zero risk.

### Level 2: SUBSTITUTE

**Local JSON Database** - Substitute cloud APIs with local data.

**How**: `data/app_db.json` instead of calling external services.

**Why**:
- No network dependency
- No data leakage to third parties
- User can audit database contents
- Offline functionality

**Trade-off**: Database may be less current, but privacy worth it.

### Level 3: CONTROL

**Consent Framework + Ephemeral Storage** - Control risks through safeguards.

**How**:
- Explicit consent before system access
- Ephemeral storage (cleared after session)
- Audit logging (in memory only)
- User-controlled exports

**When**: Full Audit mode with automatic scanning.

**Why**: Balances functionality with safety.

### Why This Order Matters

Traditional software often starts at Level 3 (controls) without considering elimination or substitution. Juisys explicitly implements all three levels, defaulting to most protective (ELIMINATE).

---

## Calm Technology Principles

Juisys demonstrates Calm Technology through ambient computing features.

### Principle 1: Technology Should Require Minimum Attention

**Implementation**: Glanceable visual indicators (color-coded risk levels).

**Example**: 🔴 Red for HIGH risk immediately communicates severity without reading text.

```julia
# Visual indicator without demanding focus
color = Ambient.color_for_risk("HIGH")  # Returns red RGB
```

### Principle 2: Technology Should Inform, Not Demand

**Implementation**: Proportional audio feedback.

**Example**:
- CRITICAL risk = 3 beeps
- HIGH risk = 2 beeps
- MEDIUM risk = 1 beep
- LOW/NONE = silent

User is informed of severity without forcing attention.

### Principle 3: Technology Should Make Use of Periphery

**Implementation**: IoT notifications (optional).

**Example**: Smart light turns red when high-risk app detected.

**Privacy**: MQTT to LOCAL broker only (localhost), requires IOT_PUBLISH consent.

### Principle 4: Technology Should Amplify Best of Technology and Humanity

**Implementation**: Automation with human oversight.

**Example**:
- Machine classifies apps quickly (technology strength)
- Human reviews and decides on alternatives (human judgment)

### Multi-Modal Feedback

```julia
# Visual (color-coded terminal)
Ambient.visual_feedback("HIGH", "Privacy concern")

# Audio (proportional beeps)
Ambient.audio_alert("HIGH")

# IoT (smart home integration)
Ambient.mqtt_notify("HIGH", "Privacy concern", broker="localhost")
```

---

## Educational Framework

Juisys is an **educational tool** that produces a **working product**.

### Learning Objectives

1. **Understand GDPR in Practice**: See all 12 processing types implemented in working code

2. **Privacy-First Architecture**: Learn architectural patterns for privacy

3. **Consent Management**: Study explicit, granular, revocable consent implementation

4. **Hazard Triangle**: Apply safety engineering to software privacy

5. **Calm Technology**: Experience multi-modal ambient computing

6. **Self-Auditing**: Understand transparency through code inspection

### Why "Educational Tool That Works"?

Many educational projects are toys. Juisys demonstrates principles through **functional software you can actually use**.

**Benefits**:
- Learning by doing (use it, see it work)
- Real-world applicability (genuine utility)
- Inspection opportunity (open source, readable code)
- Practical value (find FOSS alternatives, save money)

### Teaching "Processing is Complex"

GDPR Article 4(2) defines "processing" as any operation on data. Students often think "processing = analysis" - but it includes collection, storage, erasure, etc.

Juisys explicitly demonstrates all 12 types with code comments showing which operation implements which type.

**Example**:
```julia
"""
    manual_entry()

    GDPR: Collection processing type.
    User directly provides app data.
"""
function manual_entry()
    # ... implementation
end
```

### Automation Benefits and Risks

Juisys shows BOTH:

**Benefits** (Full Audit mode):
- Fast: Scan hundreds of apps in seconds
- Comprehensive: Won't miss anything
- Consistent: Same criteria for all apps

**Risks** (why NO PEEK mode exists):
- System access required
- Potential for over-collection
- Dependency on package manager accuracy

**Educational Point**: Automation isn't always better. Sometimes manual is safer.

---

## Attribution and Development Context

### Development Process

**Tool**: Claude Sonnet 4.5 (Anthropic)
**Date**: November 2025
**Method**: Iterative development with human oversight
**Purpose**: Educational demonstration of GDPR-compliant software design

### Why This Matters

1. **Transparency**: Users deserve to know development context

2. **Educational**: Shows what AI can create when given clear privacy requirements

3. **Accountability**: Clear attribution for code quality/issues

4. **Reproducibility**: Others can attempt similar educational projects

### What Claude Did

- Implemented all modules based on specifications
- Ensured privacy-first architecture throughout
- Created comprehensive documentation
- Built self-audit capability
- Wrote extensive comments explaining GDPR connections

### What Claude Did NOT Do

- Make network calls (verified by self-audit)
- Store personal data persistently
- Implement telemetry or tracking
- Access systems without consent requirements

### Human Responsibility

Regardless of who/what wrote code, **human users are responsible** for:
- Reviewing code before use
- Running self-audits
- Verifying privacy claims
- Ethical use of tool

---

## Ethical Use

### Intended Uses ✅

- **Personal Auditing**: Review your own installed apps
- **Education**: Learn GDPR compliance through working example
- **Research**: Study privacy-first architecture patterns
- **Advocacy**: Demonstrate feasibility of privacy-respecting software
- **Cost Analysis**: Find FOSS alternatives to save money

### Problematic Uses ⚠️

- **Surveillance**: Auditing others' systems without permission
- **Compliance Theater**: Using as GDPR checkbox without understanding
- **Blind Trust**: Not verifying privacy claims through self-audit
- **Commercial Use**: Selling without disclosure of development context

### Ethical Guidelines

1. **Consent**: Get permission before scanning anyone else's system

2. **Verification**: Always run self-audit, don't trust blindly

3. **Attribution**: If sharing/modifying, maintain attribution

4. **Education**: Use as learning tool, not just product

5. **Improvement**: Contribute findings, improvements back to community

### Limitations and Disclaimers

**Juisys is**:
- Educational demonstration
- Privacy-focused tool
- Open for inspection
- Self-auditing

**Juisys is NOT**:
- Legal compliance guarantee
- Professional security audit
- Comprehensive privacy protection
- Substitute for legal advice

**Use Responsibly**: Understand what it does, verify claims, respect others' privacy.

---

## Conclusion

Juisys demonstrates that privacy-first software is:
- **Feasible**: Can be built with current technology
- **Functional**: Doesn't sacrifice all utility for privacy
- **Verifiable**: Self-audit proves compliance
- **Educational**: Teaches through working example

**Key Takeaway**: Privacy isn't just feature, it's architectural foundation. Build it in from start, not bolted on later.

---

## Further Reading

- **GDPR Full Text**: https://gdpr-info.eu/
- **Calm Technology**: http://calmtech.com/ (Amber Case)
- **OSHA Hierarchy of Controls**: https://www.osha.gov/
- **Data Minimization**: GDPR Article 5.1.c
- **Privacy by Design**: GDPR Article 25

---

## Questions?

Review the code, run the self-audit, experiment safely. That's the educational value - learn by doing, verify by inspecting.

**Privacy is not magic. It's intentional design. Juisys shows how.**
