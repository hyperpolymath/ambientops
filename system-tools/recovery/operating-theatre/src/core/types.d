// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// Core types for the plan-first system management toolkit

module core.types;

import std.datetime;
import std.json;
import std.uuid;

/// Reversibility classification for actions
enum Reversibility
{
    full,       /// Can be completely undone
    partial,    /// Can be partially undone
    none        /// Cannot be undone (destructive)
}

/// Priority level for findings and actions
enum Priority
{
    critical,
    high,
    medium,
    low,
    info
}

/// Status of a plan step
enum StepStatus
{
    pending,
    running,
    completed,
    failed,
    skipped,
    undone
}

/// A single piece of evidence collected during scan
struct Evidence
{
    string id;
    string category;        // e.g., "disk", "service", "security"
    string description;
    string currentValue;
    string expectedValue;   // empty if just informational
    Priority priority;
    SysTime timestamp;
    string[string] metadata;

    static Evidence create(string category, string description)
    {
        Evidence e;
        e.id = randomUUID().toString();
        e.category = category;
        e.description = description;
        e.timestamp = Clock.currTime();
        e.priority = Priority.info;
        return e;
    }
}

/// A proposed action step in a plan
struct Step
{
    string id;
    string name;
    string description;
    string command;         // what will be executed
    string preview;         // human-readable preview
    Reversibility reversibility;
    string undoCommand;     // command to reverse (if reversible)
    bool requiresElevation; // needs sudo
    StepStatus status;
    string[string] metadata;

    static Step create(string name, string description)
    {
        Step s;
        s.id = randomUUID().toString();
        s.name = name;
        s.description = description;
        s.status = StepStatus.pending;
        s.reversibility = Reversibility.none;
        return s;
    }
}

/// An undo token generated when a step is applied
struct UndoToken
{
    string id;
    string stepId;
    string undoCommand;
    string backupPath;      // path to backup data if any
    SysTime createdAt;
    bool used;

    static UndoToken create(string stepId, string undoCommand)
    {
        UndoToken t;
        t.id = randomUUID().toString();
        t.stepId = stepId;
        t.undoCommand = undoCommand;
        t.createdAt = Clock.currTime();
        t.used = false;
        return t;
    }
}

/// A complete plan ready for approval
struct Plan
{
    string id;
    string name;
    string description;
    Step[] steps;
    Evidence[] evidence;    // evidence that led to this plan
    SysTime createdAt;
    bool approved;
    string approvedBy;      // "user" or empty

    static Plan create(string name, string description)
    {
        Plan p;
        p.id = randomUUID().toString();
        p.name = name;
        p.description = description;
        p.createdAt = Clock.currTime();
        p.approved = false;
        return p;
    }

    /// Count steps by reversibility
    void countByReversibility(out int full, out int partial, out int none)
    {
        full = 0;
        partial = 0;
        none = 0;
        foreach (step; steps)
        {
            final switch (step.reversibility)
            {
                case Reversibility.full:
                    full++;
                    break;
                case Reversibility.partial:
                    partial++;
                    break;
                case Reversibility.none:
                    none++;
                    break;
            }
        }
    }

    /// Check if plan has any irreversible steps
    bool hasIrreversibleSteps()
    {
        foreach (step; steps)
            if (step.reversibility == Reversibility.none)
                return true;
        return false;
    }
}

/// Result of applying a plan
struct ApplyResult
{
    string planId;
    bool success;
    Step[] completedSteps;
    Step[] failedSteps;
    UndoToken[] undoTokens;
    SysTime startedAt;
    SysTime completedAt;
    string errorMessage;
}

/// An audit receipt documenting what was done
struct Receipt
{
    string id;
    string planId;
    SysTime timestamp;
    Evidence[] scannedEvidence;
    Step[] proposedSteps;
    Step[] executedSteps;
    Step[] skippedSteps;
    UndoToken[] undoTokens;
    string summary;
    string[string] metadata;

    static Receipt create(string planId)
    {
        Receipt r;
        r.id = randomUUID().toString();
        r.planId = planId;
        r.timestamp = Clock.currTime();
        return r;
    }

    /// Generate human-readable summary
    string generateSummary()
    {
        import std.format : format;
        return format(
            "Receipt %s\n" ~
            "Plan: %s\n" ~
            "Time: %s\n" ~
            "Evidence collected: %d items\n" ~
            "Steps proposed: %d\n" ~
            "Steps executed: %d\n" ~
            "Steps skipped: %d\n" ~
            "Undo tokens: %d\n",
            id[0 .. 8],
            planId[0 .. 8],
            timestamp.toISOExtString(),
            scannedEvidence.length,
            proposedSteps.length,
            executedSteps.length,
            skippedSteps.length,
            undoTokens.length
        );
    }
}

/// Envelope containing scan results
struct ScanEnvelope
{
    string id;
    string scanType;        // e.g., "system", "cleanup", "repos"
    SysTime timestamp;
    Evidence[] evidence;
    string[string] metadata;

    static ScanEnvelope create(string scanType)
    {
        ScanEnvelope e;
        e.id = randomUUID().toString();
        e.scanType = scanType;
        e.timestamp = Clock.currTime();
        return e;
    }
}
