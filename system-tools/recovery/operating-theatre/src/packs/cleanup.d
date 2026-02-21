// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// Cleanup pack - cache and temp file cleanup with plan-first approach

module packs.cleanup;

import core.types;
import std.stdio;
import std.process;
import std.file;
import std.path;
import std.string;
import std.format;
import std.algorithm;
import core.engine : getHomeDir;

/// Get home directory at runtime
string homeDir()
{
    return getHomeDir();
}

/// Cleanup target definition
struct CleanupTarget
{
    string name;
    string path;
    Priority priority;
    bool recursive;
}

/// Get list of cleanup targets
CleanupTarget[] getCleanupTargets()
{
    string home = homeDir();
    return [
        CleanupTarget("debuginfod cache", buildPath(home, ".cache/debuginfod_client"), Priority.high, true),
        CleanupTarget("npm cache", buildPath(home, ".npm"), Priority.medium, true),
        CleanupTarget("bun cache", buildPath(home, ".bun"), Priority.medium, true),
        CleanupTarget("pip cache", buildPath(home, ".cache/pip"), Priority.medium, true),
        CleanupTarget("cargo cache", buildPath(home, ".cargo/registry/cache"), Priority.medium, true),
        CleanupTarget("go mod cache", buildPath(home, "go/pkg/mod/cache"), Priority.medium, true),
        CleanupTarget("thumbnails", buildPath(home, ".cache/thumbnails"), Priority.low, true),
        CleanupTarget("Edge Dev cache", buildPath(home, ".var/app/com.microsoft.EdgeDev/cache"), Priority.medium, true),
        CleanupTarget("partial downloads", buildPath(home, "Downloads") ~ "/*.part", Priority.low, false),
        CleanupTarget("vim undo", buildPath(home, ".local/state/nvim/undo"), Priority.low, true),
    ];
}

/// Calculate directory size
ulong getDirSize(string path)
{
    ulong size = 0;
    try
    {
        if (path.canFind("*"))
        {
            // Glob pattern - estimate
            auto result = executeShell("du -sb " ~ path ~ " 2>/dev/null | cut -f1");
            if (result.status == 0 && result.output.strip().length > 0)
            {
                import std.conv : to;
                try { size = result.output.strip().to!ulong; } catch (Exception e) {}
            }
        }
        else if (exists(path) && isDir(path))
        {
            foreach (entry; dirEntries(path, SpanMode.depth))
            {
                if (entry.isFile)
                    size += entry.size;
            }
        }
    }
    catch (Exception e)
    {
        // Permission errors, etc.
    }
    return size;
}

/// Format size for display
string formatSize(ulong bytes)
{
    if (bytes >= 1_073_741_824)
        return format("%.1f GB", bytes / 1_073_741_824.0);
    else if (bytes >= 1_048_576)
        return format("%.1f MB", bytes / 1_048_576.0);
    else if (bytes >= 1024)
        return format("%.1f KB", bytes / 1024.0);
    else
        return format("%d B", bytes);
}

/// Scan for cleanup opportunities
ScanEnvelope scanCleanup()
{
    auto envelope = ScanEnvelope.create("cleanup");

    writeln("=== Scanning for Cleanup Opportunities ===");
    writeln("");

    ulong totalSize = 0;

    foreach (target; getCleanupTargets())
    {
        bool exists_target = false;

        if (target.path.canFind("*"))
        {
            auto result = executeShell("ls " ~ target.path ~ " 2>/dev/null | head -1");
            exists_target = result.output.strip().length > 0;
        }
        else
        {
            exists_target = exists(target.path);
        }

        if (exists_target)
        {
            ulong size = getDirSize(target.path);
            totalSize += size;

            auto e = Evidence.create("cleanup", target.name);
            e.currentValue = formatSize(size);
            e.priority = target.priority;
            e.description = format("%s: %s", target.name, formatSize(size));
            e.metadata["path"] = target.path;
            e.metadata["size_bytes"] = format("%d", size);
            e.metadata["recursive"] = target.recursive ? "true" : "false";

            envelope.evidence ~= e;
            writefln("  [%s] %s", e.priority, e.description);
        }
    }

    writeln("");
    writefln("Total cleanable: %s across %d targets", formatSize(totalSize), envelope.evidence.length);

    return envelope;
}

/// Generate cleanup plan based on evidence
Plan planCleanup(ScanEnvelope scan, bool allPriorities = false)
{
    auto plan = Plan.create("cleanup", "Clean caches and temporary files");
    plan.evidence = scan.evidence;

    writeln("");
    writeln("=== Generating Cleanup Plan ===");
    writeln("");

    foreach (e; scan.evidence)
    {
        // Skip low priority unless --all
        if (!allPriorities && e.priority == Priority.low)
            continue;

        string path = e.metadata.get("path", "");
        bool recursive = e.metadata.get("recursive", "true") == "true";

        if (path.length == 0)
            continue;

        auto step = Step.create("clean-" ~ e.category, "Remove " ~ e.description);

        if (path.canFind("*"))
        {
            step.command = "rm -f " ~ path ~ " 2>/dev/null";
        }
        else if (recursive)
        {
            step.command = "rm -rf " ~ path ~ " 2>/dev/null";
        }
        else
        {
            step.command = "rm -f " ~ path ~ " 2>/dev/null";
        }

        step.preview = "Delete: " ~ path;
        step.reversibility = Reversibility.none; // Cannot recover deleted caches
        step.requiresElevation = false;
        step.metadata["freed_estimate"] = e.currentValue;

        plan.steps ~= step;
    }

    writefln("Plan generated: %d cleanup steps", plan.steps.length);

    // Warn about irreversibility
    if (plan.steps.length > 0)
    {
        writeln("");
        writeln("⚠ NOTE: Cleanup operations are not reversible.");
        writeln("  Caches will be regenerated as needed by applications.");
    }

    return plan;
}
