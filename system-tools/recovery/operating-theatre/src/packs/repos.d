// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// Repos pack - repository management with plan-first approach

module packs.repos;

import core.types;
import std.stdio;
import std.process;
import std.file;
import std.path;
import std.string;
import std.algorithm;
import std.array;
import core.engine : getHomeDir;

/// Get repos directory - defaults to ~/repos or uses SOR_REPOS_DIR env var
string reposDir()
{
    import std.process : environment;
    auto customDir = environment.get("SOR_REPOS_DIR", "");
    if (customDir.length > 0)
        return customDir;
    return buildPath(getHomeDir(), "repos");
}

/// Repository status
struct RepoStatus
{
    string name;
    string path;
    bool hasChanges;
    bool aheadOfRemote;
    bool behindRemote;
    int uncommittedFiles;
    string branch;
}

/// Get list of git repositories
string[] getRepos()
{
    string[] repos;
    auto rdir = reposDir();

    if (!exists(rdir))
        return repos;

    foreach (entry; dirEntries(rdir, SpanMode.shallow))
    {
        if (entry.isDir)
        {
            string gitPath = buildPath(entry.name, ".git");
            if (exists(gitPath))
                repos ~= entry.name;
        }
    }

    return repos;
}

/// Get status of a single repo
RepoStatus getRepoStatus(string repoPath)
{
    RepoStatus status;
    status.path = repoPath;
    status.name = baseName(repoPath);

    // Get current branch
    auto branchResult = executeShell("cd " ~ repoPath ~ " && git branch --show-current 2>/dev/null");
    status.branch = branchResult.output.strip();

    // Check for uncommitted changes
    auto statusResult = executeShell("cd " ~ repoPath ~ " && git status --porcelain 2>/dev/null");
    status.hasChanges = statusResult.output.strip().length > 0;
    status.uncommittedFiles = cast(int) statusResult.output.strip().split("\n")
        .filter!(line => line.length > 0).array.length;

    // Check ahead/behind (requires fetch first for accuracy)
    auto aheadResult = executeShell("cd " ~ repoPath ~ " && git rev-list --count @{u}..HEAD 2>/dev/null");
    if (aheadResult.status == 0)
    {
        import std.conv : to;
        try
        {
            status.aheadOfRemote = aheadResult.output.strip().to!int > 0;
        }
        catch (Exception e) {}
    }

    auto behindResult = executeShell("cd " ~ repoPath ~ " && git rev-list --count HEAD..@{u} 2>/dev/null");
    if (behindResult.status == 0)
    {
        import std.conv : to;
        try
        {
            status.behindRemote = behindResult.output.strip().to!int > 0;
        }
        catch (Exception e) {}
    }

    return status;
}

/// Scan repositories for status
ScanEnvelope scanRepos()
{
    auto envelope = ScanEnvelope.create("repos");

    writeln("=== Scanning Repositories ===");
    writeln("");

    auto repos = getRepos();
    writefln("Found %d repositories in %s", repos.length, reposDir());
    writeln("");

    int withChanges = 0;
    int ahead = 0;
    int behind = 0;

    foreach (repoPath; repos)
    {
        auto status = getRepoStatus(repoPath);

        if (status.hasChanges || status.aheadOfRemote || status.behindRemote)
        {
            auto e = Evidence.create("repo", status.name);

            string[] issues;
            if (status.hasChanges)
            {
                issues ~= format("%d uncommitted", status.uncommittedFiles);
                withChanges++;
            }
            if (status.aheadOfRemote)
            {
                issues ~= "ahead of remote";
                ahead++;
            }
            if (status.behindRemote)
            {
                issues ~= "behind remote";
                behind++;
            }

            e.currentValue = issues.join(", ");
            e.priority = status.hasChanges ? Priority.medium : Priority.low;
            e.description = format("%s [%s]: %s", status.name, status.branch, e.currentValue);
            e.metadata["path"] = status.path;
            e.metadata["branch"] = status.branch;
            e.metadata["uncommitted"] = format("%d", status.uncommittedFiles);

            envelope.evidence ~= e;
            writefln("  [%s] %s", e.priority, e.description);
        }
    }

    writeln("");
    writefln("Summary: %d with changes, %d ahead, %d behind",
        withChanges, ahead, behind);

    return envelope;
}

/// Generate sync plan based on evidence
Plan planRepoSync(ScanEnvelope scan, bool includeWithChanges = false)
{
    auto plan = Plan.create("repo-sync", "Sync repositories with remote");
    plan.evidence = scan.evidence;

    writeln("");
    writeln("=== Generating Sync Plan ===");
    writeln("");

    auto repos = getRepos();

    foreach (repoPath; repos)
    {
        auto status = getRepoStatus(repoPath);

        // Skip repos with uncommitted changes unless forced
        if (status.hasChanges && !includeWithChanges)
        {
            writefln("  Skipping %s (has uncommitted changes)", status.name);
            continue;
        }

        // Add fetch step
        {
            auto step = Step.create("fetch-" ~ status.name, "Fetch " ~ status.name);
            step.command = "cd " ~ repoPath ~ " && git fetch --all -q";
            step.preview = "git fetch --all";
            step.reversibility = Reversibility.full; // Fetch doesn't change local state
            step.requiresElevation = false;
            plan.steps ~= step;
        }

        // Add pull step only if behind
        if (status.behindRemote || !status.hasChanges)
        {
            auto step = Step.create("pull-" ~ status.name, "Pull " ~ status.name);
            step.command = "cd " ~ repoPath ~ " && git pull -q";
            step.preview = "git pull";
            step.reversibility = Reversibility.partial; // Can reset but may lose work
            step.requiresElevation = false;
            plan.steps ~= step;
        }
    }

    writefln("Plan generated: %d sync steps", plan.steps.length);

    return plan;
}

/// Check command - just show status without planning
void checkRepos()
{
    writeln("=== Repository Status ===");
    writeln("");

    auto repos = getRepos();
    int withChanges = 0;

    foreach (repoPath; repos)
    {
        auto status = getRepoStatus(repoPath);

        if (status.hasChanges)
        {
            writefln("=== %s [%s] ===", status.name, status.branch);

            auto shortResult = executeShell("cd " ~ repoPath ~ " && git status --short | head -8");
            writeln(shortResult.output);
            withChanges++;
        }
    }

    if (withChanges == 0)
        writeln("All repositories are clean!");
    else
        writefln("\n%d repositories have uncommitted changes", withChanges);
}
