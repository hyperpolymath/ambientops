// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// Ecosystem integration - connects to AmbientOps ecosystem
//
// System Operating Theatre → produces run bundles
// System Observatory → ingests run bundles for correlation/forecasting
// Ward → displays system weather/state
// PSA → receives trend alerts

module core.ecosystem;

import core.types;
import core.security;
import std.stdio;
import std.file;
import std.path;
import std.json;
import std.datetime;
import std.string;
import std.process;
import std.conv : to;

/// Run bundle format version
enum RUN_BUNDLE_VERSION = "1.0.0";

// Import path utilities from engine
import core.engine : getHomeDir, getDataDir, runBundleDir;

/// Get Observatory inbox directory
string observatoryInbox()
{
    return buildPath(getDataDir(), "ambientops", "observatory", "inbox");
}

/// Run bundle - complete record of a plan execution
struct RunBundle
{
    string id;
    string version_;       // Using version_ to avoid D keyword conflict
    SysTime timestamp;
    string planId;
    string planName;

    // Evidence envelope
    Evidence[] evidence;

    // Execution record
    Step[] proposedSteps;
    Step[] executedSteps;
    Step[] skippedSteps;
    Step[] failedSteps;

    // Undo capability
    UndoToken[] undoTokens;

    // Metadata for Observatory correlation
    string hostname;
    string username;
    string osVersion;
    string sorVersion;

    static RunBundle create(string planId, string planName)
    {
        RunBundle b;
        b.id = generateSecureId();
        b.version_ = RUN_BUNDLE_VERSION;
        b.timestamp = Clock.currTime();
        b.planId = planId;
        b.planName = planName;

        // Collect system metadata
        auto hostnameResult = executeShell("hostname 2>/dev/null");
        b.hostname = hostnameResult.output.strip();

        auto userResult = executeShell("whoami 2>/dev/null");
        b.username = userResult.output.strip();

        auto osResult = executeShell("cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"'");
        b.osVersion = osResult.output.strip();

        b.sorVersion = "0.1.0"; // TODO: Get from build

        return b;
    }
}

/// Export run bundle to JSON for Observatory ingestion
JSONValue bundleToJson(RunBundle bundle)
{
    JSONValue json;
    json["id"] = bundle.id;
    json["version"] = bundle.version_;
    json["timestamp"] = bundle.timestamp.toISOExtString();
    json["planId"] = bundle.planId;
    json["planName"] = bundle.planName;

    // Metadata
    JSONValue meta;
    meta["hostname"] = bundle.hostname;
    meta["username"] = bundle.username;
    meta["osVersion"] = bundle.osVersion;
    meta["sorVersion"] = bundle.sorVersion;
    json["metadata"] = meta;

    // Summary counts
    JSONValue summary;
    summary["evidenceCount"] = bundle.evidence.length;
    summary["proposedCount"] = bundle.proposedSteps.length;
    summary["executedCount"] = bundle.executedSteps.length;
    summary["skippedCount"] = bundle.skippedSteps.length;
    summary["failedCount"] = bundle.failedSteps.length;
    summary["undoTokenCount"] = bundle.undoTokens.length;
    json["summary"] = summary;

    // Evidence (simplified for Observatory)
    JSONValue[] evidenceArray;
    foreach (e; bundle.evidence)
    {
        JSONValue ev;
        ev["id"] = e.id;
        ev["category"] = e.category;
        ev["description"] = e.description;
        ev["priority"] = e.priority.to!string;
        ev["timestamp"] = e.timestamp.toISOExtString();
        evidenceArray ~= ev;
    }
    json["evidence"] = JSONValue(evidenceArray);

    // Steps (simplified)
    JSONValue[] stepsArray;
    foreach (s; bundle.executedSteps)
    {
        JSONValue step;
        step["id"] = s.id;
        step["name"] = s.name;
        step["status"] = s.status.to!string;
        step["reversibility"] = s.reversibility.to!string;
        stepsArray ~= step;
    }
    json["executedSteps"] = JSONValue(stepsArray);

    return json;
}

/// Save run bundle to local storage
string saveRunBundle(RunBundle bundle)
{
    auto bundleDir = runBundleDir();
    // Ensure directories exist with secure permissions
    if (!exists(bundleDir))
        mkdirRecurse(bundleDir);
    secureRunBundle(bundleDir);

    string filename = format("%s/bundle-%s.json",
        bundleDir,
        bundle.timestamp.toISOExtString().replace(":", "-"));

    auto json = bundleToJson(bundle);
    std.file.write(filename, json.toPrettyString());
    secureFile(filename);

    writefln("Run bundle saved: %s", filename);
    return filename;
}

/// Export run bundle to Observatory inbox (if available)
bool exportToObservatory(RunBundle bundle)
{
    auto inbox = observatoryInbox();
    if (!exists(inbox))
    {
        writeln("Observatory inbox not found - bundle saved locally only");
        return false;
    }

    string filename = format("%s/bundle-%s-%s.json",
        inbox,
        bundle.hostname,
        bundle.timestamp.toISOExtString().replace(":", "-"));

    auto json = bundleToJson(bundle);
    std.file.write(filename, json.toPrettyString());

    writefln("Run bundle exported to Observatory: %s", filename);
    return true;
}

/// Create run bundle from plan execution result
RunBundle createRunBundle(Plan plan, ApplyResult result)
{
    auto bundle = RunBundle.create(plan.id, plan.name);
    bundle.evidence = plan.evidence;
    bundle.proposedSteps = plan.steps;
    bundle.executedSteps = result.completedSteps;
    bundle.undoTokens = result.undoTokens;

    foreach (step; plan.steps)
    {
        if (step.status == StepStatus.skipped)
            bundle.skippedSteps ~= step;
        if (step.status == StepStatus.failed)
            bundle.failedSteps ~= step;
    }

    return bundle;
}

/// Check ecosystem connectivity
struct EcosystemStatus
{
    bool observatoryAvailable;
    bool wardAvailable;
    bool psaAvailable;
    string[] messages;
}

EcosystemStatus checkEcosystem()
{
    EcosystemStatus status;

    // Check Observatory
    status.observatoryAvailable = exists(observatoryInbox());
    if (status.observatoryAvailable)
        status.messages ~= "Observatory: connected";
    else
        status.messages ~= "Observatory: not available (local mode)";

    // Ward and PSA would be checked via network/IPC
    // For now, they're not available in local mode
    status.wardAvailable = false;
    status.psaAvailable = false;
    status.messages ~= "Ward: not connected";
    status.messages ~= "PSA: not connected";

    return status;
}

/// Print ecosystem status
void printEcosystemStatus()
{
    writeln("=== AmbientOps Ecosystem Status ===");
    writeln("");

    auto status = checkEcosystem();
    foreach (msg; status.messages)
        writefln("  %s", msg);

    writeln("");
    writeln("Run bundles are saved locally and exported to Observatory when available.");
}
