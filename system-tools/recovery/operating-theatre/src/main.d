// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// System Operating Theatre - Main Entry Point
// A plan-first system management and hardening tool

module main;

import std.stdio;
import std.getopt;
import std.string;
import std.file;

import core.types;
import core.engine : applyPlan, executeUndo, generateReceipt, saveReceipt,
                      saveUndoTokens, printPlanPreview, getHomeDir, runBundleDir;
import core.security;
import std.path;
import core.ecosystem;
import packs.system;
import packs.cleanup;
import packs.repos;
import packs.diagnostics;
import std.conv : to;

/// Version info
enum VERSION = "0.1.0";
enum NAME = "System Operating Theatre";
enum BINARY = "sor";

void main(string[] args)
{
    // Security check
    warnIfRoot();

    if (args.length < 2)
    {
        printUsage();
        return;
    }

    string command = args[1];
    string[] subArgs = args.length > 2 ? args[2 .. $] : [];

    switch (command)
    {
        // Plan-first workflow
        case "scan":
            cmdScan(subArgs);
            break;
        case "plan":
            cmdPlan(subArgs);
            break;
        case "apply":
            cmdApply(subArgs);
            break;
        case "undo":
            cmdUndo(subArgs);
            break;
        case "receipt":
            cmdReceipt(subArgs);
            break;

        // Quick commands (scan+plan+apply in one)
        case "quick":
            cmdQuick(subArgs);
            break;

        // Utility commands
        case "check":
            checkRepos();
            break;
        case "status":
            cmdStatus(subArgs);
            break;

        // Help and version
        case "help":
        case "--help":
        case "-h":
            printUsage();
            break;
        case "version":
        case "--version":
        case "-v":
            printVersion();
            break;

        default:
            stderr.writefln("Unknown command: %s", command);
            stderr.writeln("Run 'sor help' for usage information.");
    }
}

void printVersion()
{
    writefln("%s v%s", NAME, VERSION);
    writeln("A plan-first system management tool");
    writeln("");
    writeln("Part of the AmbientOps ecosystem:");
    writeln("  Operating Theatre → applies changes safely");
    writeln("  Observatory → observes and correlates");
    writeln("  Ward → displays system weather");
}

void printUsage()
{
    writefln("%s v%s", NAME, VERSION);
    writeln("");
    writeln("Usage: sor <command> [options]");
    writeln("");
    writeln("PLAN-FIRST WORKFLOW:");
    writeln("  scan <pack>        Collect evidence (no changes)");
    writeln("  plan <pack>        Generate plan from scan results");
    writeln("  apply              Execute approved plan");
    writeln("  undo               Roll back using saved undo tokens");
    writeln("  receipt            Show execution receipts");
    writeln("");
    writeln("PACKS:");
    writeln("  system             System optimization (firewall, journal, network)");
    writeln("  cleanup            Clean caches and temporary files");
    writeln("  repos              Repository synchronization");
    writeln("  diagnostics|diag   System health diagnostics (OS, memory, disks, services)");
    writeln("");
    writeln("QUICK COMMANDS:");
    writeln("  quick <pack>       Scan + plan + preview (no apply without --yes)");
    writeln("  check              Show repositories with uncommitted changes");
    writeln("  status             Show ecosystem status");
    writeln("");
    writeln("OPTIONS:");
    writeln("  --dry-run          Preview without making changes");
    writeln("  --yes              Auto-approve plan (use with caution)");
    writeln("  --all              Include all priorities (cleanup: include low)");
    writeln("");
    writeln("EXAMPLES:");
    writeln("  sor scan system             # Collect system evidence");
    writeln("  sor plan system             # Generate optimization plan");
    writeln("  sor apply --dry-run         # Preview what would be applied");
    writeln("  sor apply                   # Execute the plan");
    writeln("  sor quick cleanup --yes     # Quick cleanup with auto-approve");
    writeln("  sor undo                    # Roll back last changes");
    writeln("  sor receipt                 # Show execution history");
    writeln("");
    writeln("PHILOSOPHY:");
    writeln("  • Scan before plan, plan before apply");
    writeln("  • Show evidence, not hype");
    writeln("  • Prefer reversible actions");
    writeln("  • Always produce receipts");
}

// ============================================================================
// Command implementations
// ============================================================================

void cmdScan(string[] args)
{
    string pack = "";
    if (args.length > 0)
        pack = args[0];

    if (pack.length == 0)
    {
        stderr.writeln("Error: specify a pack to scan (system, cleanup, repos)");
        return;
    }

    ScanEnvelope envelope;

    switch (pack)
    {
        case "system":
            envelope = scanSystem();
            break;
        case "cleanup":
            envelope = scanCleanup();
            break;
        case "repos":
            envelope = scanRepos();
            break;
        case "diagnostics":
        case "diag":
            envelope = scanDiagnostics();
            break;
        default:
            stderr.writefln("Unknown pack: %s", pack);
            return;
    }

    // Save scan envelope for plan command
    saveScanEnvelope(envelope);
}

void cmdPlan(string[] args)
{
    string pack = "";
    bool showOnly = false;

    getopt(args,
        "show", &showOnly
    );

    if (args.length > 0)
        pack = args[0];

    if (pack.length == 0)
    {
        stderr.writeln("Error: specify a pack to plan (system, cleanup, repos)");
        return;
    }

    // Load saved scan envelope
    auto envelope = loadScanEnvelope(pack);
    if (envelope.evidence.length == 0)
    {
        stderr.writefln("No scan data found for '%s'. Run 'sor scan %s' first.", pack, pack);
        return;
    }

    Plan plan;

    switch (pack)
    {
        case "system":
            plan = planSystemOptimization(envelope);
            break;
        case "cleanup":
            plan = planCleanup(envelope);
            break;
        case "repos":
            plan = planRepoSync(envelope);
            break;
        case "diagnostics":
        case "diag":
            plan = planDiagnostics(envelope);
            break;
        default:
            stderr.writefln("Unknown pack: %s", pack);
            return;
    }

    writeln("");
    printPlanPreview(plan);

    // Save plan for apply command
    savePlan(plan);

    writeln("");
    writeln("To apply this plan:");
    writeln("  sor apply --dry-run    # Preview");
    writeln("  sor apply              # Execute");
}

void cmdApply(string[] args)
{
    bool dryRun = false;
    bool autoApprove = false;

    getopt(args,
        "dry-run", &dryRun,
        "yes", &autoApprove
    );

    // Load saved plan
    auto plan = loadPlan();
    if (plan.steps.length == 0)
    {
        stderr.writeln("No plan found. Run 'sor plan <pack>' first.");
        return;
    }

    if (!dryRun && !autoApprove && !plan.approved)
    {
        writeln("");
        printPlanPreview(plan);
        writeln("");
        write("Apply this plan? [y/N] ");
        stdout.flush();

        string response;
        try
        {
            response = stdin.readln().strip().toLower();
        }
        catch (Exception e)
        {
            response = "";
        }

        if (response != "y" && response != "yes")
        {
            writeln("Plan not approved. Aborting.");
            return;
        }

        plan = approvePlan(plan);
    }
    else if (autoApprove)
    {
        plan = approvePlan(plan);
    }

    // Apply the plan
    auto result = applyPlan(plan, dryRun);

    if (!dryRun)
    {
        // Create and save run bundle
        auto bundle = createRunBundle(plan, result);
        saveRunBundle(bundle);

        // Export to Observatory if available
        exportToObservatory(bundle);

        // Save undo tokens
        saveUndoTokens(result.undoTokens, plan.id);

        // Generate and save receipt
        auto receipt = generateReceipt(plan, result);
        saveReceipt(receipt);
    }
}

void cmdUndo(string[] args)
{
    writeln("=== Undo Last Changes ===");
    writeln("");

    // Load most recent undo tokens
    auto tokens = loadUndoTokens();

    if (tokens.length == 0)
    {
        writeln("No undo tokens available.");
        return;
    }

    writefln("Found %d undo tokens", tokens.length);
    writeln("");

    foreach (i, token; tokens)
    {
        writefln("%d. Step %s", i + 1, token.stepId[0 .. 8]);
        writefln("   Command: %s", token.undoCommand);
        writefln("   Used: %s", token.used ? "yes" : "no");
    }

    writeln("");
    write("Execute undo? [y/N] ");
    stdout.flush();

    string response;
    try
    {
        response = stdin.readln().strip().toLower();
    }
    catch (Exception e)
    {
        response = "";
    }

    if (response != "y" && response != "yes")
    {
        writeln("Undo cancelled.");
        return;
    }

    // Execute undo in reverse order
    int undone = 0;
    foreach_reverse (ref token; tokens)
    {
        if (!token.used && executeUndo(token))
            undone++;
    }

    writeln("");
    writefln("Undone %d steps", undone);
}

void cmdReceipt(string[] args)
{
    writeln("=== Execution Receipts ===");
    writeln("");

    string runDir = runBundleDir();
    if (!exists(runDir))
    {
        writeln("No receipts found.");
        return;
    }

    int count = 0;
    foreach (entry; dirEntries(runDir, "receipt-*.json", SpanMode.shallow))
    {
        try
        {
            auto content = cast(string) read(entry.name);
            import std.json : parseJSON;
            auto json = parseJSON(content);
            writefln("Receipt: %s", json["id"].str[0 .. 8]);
            writefln("  Plan: %s", json["planId"].str[0 .. 8]);
            writefln("  Time: %s", json["timestamp"].str);
            writefln("  Executed: %d steps", json["executedCount"].integer);
            writeln("");
            count++;
        }
        catch (Exception e)
        {
            // Skip malformed receipts
        }
    }

    if (count == 0)
        writeln("No receipts found.");
    else
        writefln("Total: %d receipts", count);
}

void cmdQuick(string[] args)
{
    string pack = "";
    bool dryRun = false;
    bool autoApprove = false;
    bool all = false;

    getopt(args,
        "dry-run", &dryRun,
        "yes", &autoApprove,
        "all", &all
    );

    if (args.length > 0)
        pack = args[0];

    if (pack.length == 0)
    {
        stderr.writeln("Error: specify a pack (system, cleanup, repos)");
        return;
    }

    // Scan
    ScanEnvelope envelope;
    switch (pack)
    {
        case "system":
            envelope = scanSystem();
            break;
        case "cleanup":
            envelope = scanCleanup();
            break;
        case "repos":
            envelope = scanRepos();
            break;
        case "diagnostics":
        case "diag":
            envelope = scanDiagnostics();
            break;
        default:
            stderr.writefln("Unknown pack: %s", pack);
            return;
    }

    // Plan
    Plan plan;
    switch (pack)
    {
        case "system":
            plan = planSystemOptimization(envelope);
            break;
        case "cleanup":
            plan = planCleanup(envelope, all);
            break;
        case "repos":
            plan = planRepoSync(envelope);
            break;
        case "diagnostics":
        case "diag":
            plan = planDiagnostics(envelope);
            break;
        default:
            return;
    }

    writeln("");
    printPlanPreview(plan);

    if (autoApprove || dryRun)
    {
        plan = approvePlan(plan);
        auto result = applyPlan(plan, dryRun);

        if (!dryRun)
        {
            auto bundle = createRunBundle(plan, result);
            saveRunBundle(bundle);
            exportToObservatory(bundle);
            saveUndoTokens(result.undoTokens, plan.id);
        }
    }
    else
    {
        writeln("");
        writeln("To apply this plan, run: sor apply");
        saveScanEnvelope(envelope);
        savePlan(plan);
    }
}

void cmdStatus(string[] args)
{
    printVersion();
    writeln("");
    printEcosystemStatus();
}

// ============================================================================
// Persistence helpers
// ============================================================================

/// Get cache directory from XDG or fallback
string cacheDir()
{
    import std.process : environment;
    auto xdgCache = environment.get("XDG_CACHE_HOME", "");
    if (xdgCache.length > 0)
        return buildPath(xdgCache, "sor");
    return buildPath(getHomeDir(), ".cache", "sor");
}

void saveScanEnvelope(ScanEnvelope envelope)
{
    auto cache = cacheDir();
    if (!exists(cache))
        mkdirRecurse(cache);

    string filename = buildPath(cache, "scan-" ~ envelope.scanType ~ ".json");

    import std.json : JSONValue;
    JSONValue json;
    json["id"] = envelope.id;
    json["scanType"] = envelope.scanType;
    json["timestamp"] = envelope.timestamp.toISOExtString();

    JSONValue[] evidenceArray;
    foreach (e; envelope.evidence)
    {
        JSONValue ev;
        ev["id"] = e.id;
        ev["category"] = e.category;
        ev["description"] = e.description;
        ev["currentValue"] = e.currentValue;
        ev["expectedValue"] = e.expectedValue;
        ev["priority"] = e.priority.to!string;

        JSONValue meta;
        foreach (k, v; e.metadata)
            meta[k] = v;
        ev["metadata"] = meta;

        evidenceArray ~= ev;
    }
    json["evidence"] = JSONValue(evidenceArray);

    std.file.write(filename, json.toPrettyString());
    secureFile(filename);
}

ScanEnvelope loadScanEnvelope(string scanType)
{
    ScanEnvelope envelope;
    string filename = buildPath(cacheDir(), "scan-" ~ scanType ~ ".json");

    if (!exists(filename))
        return envelope;

    try
    {
        import std.json : parseJSON;
        auto content = cast(string) read(filename);
        auto json = parseJSON(content);

        envelope.id = json["id"].str;
        envelope.scanType = json["scanType"].str;

        foreach (ev; json["evidence"].array)
        {
            Evidence e;
            e.id = ev["id"].str;
            e.category = ev["category"].str;
            e.description = ev["description"].str;
            e.currentValue = ev["currentValue"].str;
            e.expectedValue = ev["expectedValue"].str;

            // Parse priority
            string prioStr = ev["priority"].str;
            switch (prioStr)
            {
                case "critical": e.priority = Priority.critical; break;
                case "high": e.priority = Priority.high; break;
                case "medium": e.priority = Priority.medium; break;
                case "low": e.priority = Priority.low; break;
                default: e.priority = Priority.info; break;
            }

            // Parse metadata
            if ("metadata" in ev)
            {
                foreach (string k, v; ev["metadata"].object)
                    e.metadata[k] = v.str;
            }

            envelope.evidence ~= e;
        }
    }
    catch (Exception e)
    {
        // Return empty envelope on error
    }

    return envelope;
}

void savePlan(Plan plan)
{
    auto cache = cacheDir();
    if (!exists(cache))
        mkdirRecurse(cache);

    string filename = buildPath(cache, "current-plan.json");

    import std.json : JSONValue;
    JSONValue json;
    json["id"] = plan.id;
    json["name"] = plan.name;
    json["description"] = plan.description;
    json["approved"] = plan.approved;

    JSONValue[] stepsArray;
    foreach (s; plan.steps)
    {
        JSONValue step;
        step["id"] = s.id;
        step["name"] = s.name;
        step["description"] = s.description;
        step["command"] = s.command;
        step["preview"] = s.preview;
        step["reversibility"] = s.reversibility.to!string;
        step["undoCommand"] = s.undoCommand;
        step["requiresElevation"] = s.requiresElevation;
        stepsArray ~= step;
    }
    json["steps"] = JSONValue(stepsArray);

    std.file.write(filename, json.toPrettyString());
    secureFile(filename);
}

Plan loadPlan()
{
    Plan plan;
    string filename = buildPath(cacheDir(), "current-plan.json");

    if (!exists(filename))
        return plan;

    try
    {
        import std.json : parseJSON;
        auto content = cast(string) read(filename);
        auto json = parseJSON(content);

        plan.id = json["id"].str;
        plan.name = json["name"].str;
        plan.description = json["description"].str;
        plan.approved = json["approved"].boolean;

        foreach (s; json["steps"].array)
        {
            Step step;
            step.id = s["id"].str;
            step.name = s["name"].str;
            step.description = s["description"].str;
            step.command = s["command"].str;
            step.preview = s["preview"].str;
            step.undoCommand = s["undoCommand"].str;
            step.requiresElevation = s["requiresElevation"].boolean;

            string revStr = s["reversibility"].str;
            switch (revStr)
            {
                case "full": step.reversibility = Reversibility.full; break;
                case "partial": step.reversibility = Reversibility.partial; break;
                default: step.reversibility = Reversibility.none; break;
            }

            plan.steps ~= step;
        }
    }
    catch (Exception e)
    {
        // Return empty plan on error
    }

    return plan;
}

UndoToken[] loadUndoTokens()
{
    UndoToken[] tokens;
    string runDir = runBundleDir();

    if (!exists(runDir))
        return tokens;

    // Find most recent undo file
    string[] undoFiles;
    foreach (entry; dirEntries(runDir, "undo-*.json", SpanMode.shallow))
        undoFiles ~= entry.name;

    if (undoFiles.length == 0)
        return tokens;

    // Sort and get most recent
    import std.algorithm : sort;
    undoFiles.sort!((a, b) => a > b);

    try
    {
        import std.json : parseJSON;
        auto content = cast(string) read(undoFiles[0]);
        auto json = parseJSON(content);

        foreach (t; json["tokens"].array)
        {
            UndoToken token;
            token.id = t["id"].str;
            token.stepId = t["stepId"].str;
            token.undoCommand = t["undoCommand"].str;
            token.used = t["used"].boolean;
            tokens ~= token;
        }
    }
    catch (Exception e)
    {
        // Return empty on error
    }

    return tokens;
}
