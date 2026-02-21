// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// Plan engine - coordinates scan, plan, apply, undo, receipt

module core.engine;

import core.types;
import std.stdio;
import std.file;
import std.path;
import std.datetime;
import std.json;
import std.process;
import std.string;
import std.array;

/// Get home directory from environment
string getHomeDir()
{
    import std.process : environment;
    auto home = environment.get("HOME", "");
    if (home.length == 0)
    {
        // Fallback for different platforms
        home = environment.get("USERPROFILE", "/tmp");
    }
    return home;
}

/// Get XDG data directory
string getDataDir()
{
    import std.process : environment;
    auto xdgData = environment.get("XDG_DATA_HOME", "");
    if (xdgData.length > 0)
        return xdgData;
    return buildPath(getHomeDir(), ".local", "share");
}

/// Run bundle directory for storing receipts and undo tokens
string runBundleDir()
{
    return buildPath(getDataDir(), "sor", "runs");
}

/// Initialize the run bundle directory
void initRunBundle()
{
    auto bundleDir = runBundleDir();
    if (!exists(bundleDir))
        mkdirRecurse(bundleDir);
}

/// Execute a plan step and generate undo token if reversible
ApplyResult applyStep(Step step, bool dryRun = false)
{
    ApplyResult result;
    result.startedAt = Clock.currTime();

    if (dryRun)
    {
        writefln("  [dry-run] Would execute: %s", step.name);
        step.status = StepStatus.skipped;
        result.success = true;
        result.completedAt = Clock.currTime();
        return result;
    }

    writefln("  Executing: %s", step.name);
    step.status = StepStatus.running;

    auto shellResult = executeShell(step.command);

    if (shellResult.status == 0)
    {
        step.status = StepStatus.completed;
        result.success = true;
        result.completedSteps ~= step;

        // Generate undo token if reversible
        if (step.reversibility != Reversibility.none && step.undoCommand.length > 0)
        {
            auto token = UndoToken.create(step.id, step.undoCommand);
            result.undoTokens ~= token;
        }

        writefln("    ✓ %s", step.name);
    }
    else
    {
        step.status = StepStatus.failed;
        result.success = false;
        result.failedSteps ~= step;
        result.errorMessage = shellResult.output.strip();
        writefln("    ✗ %s: %s", step.name, result.errorMessage);
    }

    result.completedAt = Clock.currTime();
    return result;
}

/// Apply an entire plan
ApplyResult applyPlan(Plan plan, bool dryRun = false)
{
    ApplyResult result;
    result.planId = plan.id;
    result.startedAt = Clock.currTime();
    result.success = true;

    writefln("=== Applying Plan: %s ===", plan.name);
    writeln("");

    if (!plan.approved && !dryRun)
    {
        result.success = false;
        result.errorMessage = "Plan not approved. Use 'sor plan --approve' first.";
        return result;
    }

    foreach (step; plan.steps)
    {
        auto stepResult = applyStep(step, dryRun);

        result.completedSteps ~= stepResult.completedSteps;
        result.failedSteps ~= stepResult.failedSteps;
        result.undoTokens ~= stepResult.undoTokens;

        if (!stepResult.success && !dryRun)
        {
            result.success = false;
            result.errorMessage = stepResult.errorMessage;
            writeln("");
            writefln("⚠ Plan execution stopped due to failure at step: %s", step.name);
            break;
        }
    }

    result.completedAt = Clock.currTime();

    writeln("");
    writefln("=== Plan %s ===", result.success ? "Completed" : "Failed");
    writefln("Steps completed: %d", result.completedSteps.length);
    writefln("Steps failed: %d", result.failedSteps.length);
    writefln("Undo tokens: %d", result.undoTokens.length);

    return result;
}

/// Execute undo using saved token
bool executeUndo(UndoToken token)
{
    if (token.used)
    {
        writefln("  ⚠ Undo token already used: %s", token.id[0 .. 8]);
        return false;
    }

    writefln("  Undoing step %s...", token.stepId[0 .. 8]);
    auto result = executeShell(token.undoCommand);

    if (result.status == 0)
    {
        token.used = true;
        writefln("    ✓ Undone");
        return true;
    }
    else
    {
        writefln("    ✗ Undo failed: %s", result.output.strip());
        return false;
    }
}

/// Generate a receipt from plan execution
Receipt generateReceipt(Plan plan, ApplyResult result)
{
    Receipt receipt = Receipt.create(plan.id);
    receipt.scannedEvidence = plan.evidence;
    receipt.proposedSteps = plan.steps;
    receipt.executedSteps = result.completedSteps;
    receipt.undoTokens = result.undoTokens;

    foreach (step; plan.steps)
    {
        if (step.status == StepStatus.skipped)
            receipt.skippedSteps ~= step;
    }

    receipt.summary = receipt.generateSummary();
    return receipt;
}

/// Save receipt to run bundle
void saveReceipt(Receipt receipt)
{
    initRunBundle();

    string filename = format("%s/receipt-%s.json",
        runBundleDir(),
        receipt.timestamp.toISOExtString().replace(":", "-"));

    JSONValue json;
    json["id"] = receipt.id;
    json["planId"] = receipt.planId;
    json["timestamp"] = receipt.timestamp.toISOExtString();
    json["summary"] = receipt.summary;

    // Save evidence count
    json["evidenceCount"] = receipt.scannedEvidence.length;
    json["executedCount"] = receipt.executedSteps.length;
    json["skippedCount"] = receipt.skippedSteps.length;
    json["undoTokenCount"] = receipt.undoTokens.length;

    std.file.write(filename, json.toPrettyString());
    writefln("Receipt saved: %s", filename);
}

/// Save undo tokens for later use
void saveUndoTokens(UndoToken[] tokens, string planId)
{
    if (tokens.length == 0)
        return;

    initRunBundle();

    string filename = format("%s/undo-%s.json",
        runBundleDir(),
        planId[0 .. 8]);

    JSONValue[] tokenArray;
    foreach (token; tokens)
    {
        JSONValue t;
        t["id"] = token.id;
        t["stepId"] = token.stepId;
        t["undoCommand"] = token.undoCommand;
        t["createdAt"] = token.createdAt.toISOExtString();
        t["used"] = token.used;
        tokenArray ~= t;
    }

    JSONValue json;
    json["planId"] = planId;
    json["tokens"] = JSONValue(tokenArray);

    std.file.write(filename, json.toPrettyString());
    writefln("Undo tokens saved: %s", filename);
}

/// Print plan preview
void printPlanPreview(Plan plan)
{
    writefln("=== Plan: %s ===", plan.name);
    writefln("Description: %s", plan.description);
    writefln("Created: %s", plan.createdAt.toISOExtString());
    writeln("");

    int fullRev, partialRev, noRev;
    plan.countByReversibility(fullRev, partialRev, noRev);

    writefln("Steps: %d total", plan.steps.length);
    writefln("  Fully reversible: %d", fullRev);
    writefln("  Partially reversible: %d", partialRev);
    writefln("  Not reversible: %d", noRev);
    writeln("");

    if (plan.hasIrreversibleSteps())
    {
        writeln("⚠ WARNING: This plan contains irreversible steps!");
        writeln("");
    }

    writeln("Steps:");
    foreach (i, step; plan.steps)
    {
        string revIcon = step.reversibility == Reversibility.full ? "↺" :
                        step.reversibility == Reversibility.partial ? "↻" : "⊗";
        string elevIcon = step.requiresElevation ? "🔒" : "  ";

        writefln("  %d. [%s%s] %s", i + 1, revIcon, elevIcon, step.name);
        writefln("      %s", step.description);
        if (step.preview.length > 0)
            writefln("      Preview: %s", step.preview);
    }

    writeln("");
    writeln("Legend: ↺ = fully reversible, ↻ = partial, ⊗ = not reversible, 🔒 = needs sudo");
}
