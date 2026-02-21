// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// Diagnostics pack - System health checks with plan-first approach
// Converted from system-health-check.sh for native D implementation

module packs.diagnostics;

import core.types;
import std.stdio;
import std.process;
import std.file;
import std.path;
import std.string;
import std.format;
import std.algorithm;
import std.array;
import std.conv : to;

/// Diagnostic check result
struct DiagResult
{
    string name;
    string status;     // ok, warn, error, info
    string message;
    Priority priority;
}

/// Detect operating system
DiagResult detectOS()
{
    DiagResult result;
    result.name = "Operating System";

    if (exists("/etc/os-release"))
    {
        auto content = cast(string) read("/etc/os-release");
        string prettyName = "";
        string id = "";
        string version_ = "";

        foreach (line; content.lineSplitter())
        {
            if (line.startsWith("PRETTY_NAME="))
                prettyName = line[12..$].strip().strip('"');
            else if (line.startsWith("ID="))
                id = line[3..$].strip().strip('"');
            else if (line.startsWith("VERSION_ID="))
                version_ = line[11..$].strip().strip('"');
        }

        result.message = prettyName.length > 0 ? prettyName : format("%s %s", id, version_);
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        auto osResult = executeShell("uname -s 2>/dev/null");
        result.message = osResult.output.strip();
        result.status = "info";
        result.priority = Priority.info;
    }

    return result;
}

/// Detect architecture
DiagResult detectArch()
{
    DiagResult result;
    result.name = "Architecture";

    auto archResult = executeShell("uname -m 2>/dev/null");
    string arch = archResult.output.strip();

    string archName;
    switch (arch)
    {
        case "x86_64":
        case "amd64":
            archName = "x86_64 (64-bit)";
            break;
        case "i386":
        case "i686":
            archName = "x86 (32-bit)";
            break;
        case "aarch64":
        case "arm64":
            archName = "ARM64 (64-bit)";
            break;
        case "armv7l":
            archName = "ARMv7 (32-bit)";
            break;
        default:
            archName = arch;
    }

    result.message = archName;
    result.status = "ok";
    result.priority = Priority.info;
    return result;
}

/// Detect ECC memory
DiagResult detectECC()
{
    DiagResult result;
    result.name = "ECC Memory";

    if (exists("/sys/devices/system/edac/mc"))
    {
        auto checkResult = executeShell("ls /sys/devices/system/edac/mc/mc*/csrow*/ch*_ce_count 2>/dev/null | head -1");
        if (checkResult.output.strip().length > 0)
        {
            result.message = "Detected and monitored by EDAC";
            result.status = "ok";
            result.priority = Priority.info;
            return result;
        }
    }

    // Check via DMI if available
    auto dmiResult = executeShell("dmidecode -t memory 2>/dev/null | grep -i 'error correction' | head -1");
    if (dmiResult.output.toLower().canFind("ecc"))
    {
        result.message = "Detected via DMI";
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = "Not detected (non-ECC or check requires root)";
        result.status = "info";
        result.priority = Priority.low;
    }

    return result;
}

/// Check memory status
DiagResult checkMemory()
{
    DiagResult result;
    result.name = "Memory Status";

    auto memResult = executeShell("free -h 2>/dev/null | grep Mem");
    if (memResult.status == 0)
    {
        auto parts = memResult.output.strip().split();
        if (parts.length >= 3)
        {
            result.message = format("Total: %s, Used: %s, Available: %s",
                parts[1], parts[2], parts.length > 6 ? parts[6] : "N/A");
            result.status = "ok";
            result.priority = Priority.info;
        }
    }
    else
    {
        result.message = "Unable to check memory";
        result.status = "warn";
        result.priority = Priority.medium;
    }

    return result;
}

/// Check disk health via SMART
DiagResult[] checkDiskHealth()
{
    DiagResult[] results;

    foreach (disk; ["/dev/nvme0n1", "/dev/nvme1n1", "/dev/sda", "/dev/sdb"])
    {
        if (!exists(disk))
            continue;

        DiagResult result;
        result.name = format("Disk Health: %s", disk);

        auto smartResult = executeShell("sudo smartctl -H " ~ disk ~ " 2>/dev/null");
        if (smartResult.output.canFind("PASSED") || smartResult.output.canFind("OK"))
        {
            result.message = "SMART status PASSED";
            result.status = "ok";
            result.priority = Priority.info;
        }
        else if (smartResult.status != 0)
        {
            result.message = "SMART check unavailable (may need root)";
            result.status = "info";
            result.priority = Priority.low;
        }
        else
        {
            result.message = "SMART status may need attention";
            result.status = "warn";
            result.priority = Priority.high;
        }

        results ~= result;
    }

    return results;
}

/// Check boot analysis
DiagResult checkBoot()
{
    DiagResult result;
    result.name = "Boot Time";

    auto bootResult = executeShell("systemd-analyze 2>/dev/null | head -1");
    if (bootResult.status == 0)
    {
        result.message = bootResult.output.strip();
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = "Boot analysis unavailable";
        result.status = "info";
        result.priority = Priority.low;
    }

    return result;
}

/// Check failed services
DiagResult checkServices()
{
    DiagResult result;
    result.name = "System Services";

    auto failedResult = executeShell("systemctl --failed --no-pager 2>/dev/null | grep -c 'failed' || echo 0");
    int failedCount = 0;
    try { failedCount = failedResult.output.strip().to!int; } catch (Exception e) {}

    if (failedCount == 0)
    {
        result.message = "No failed services";
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = format("%d failed service(s)", failedCount);
        result.status = "warn";
        result.priority = Priority.medium;
    }

    return result;
}

/// Check coredumps
DiagResult checkCoredumps()
{
    DiagResult result;
    result.name = "Crash Dumps";

    auto countResult = executeShell("coredumpctl list 2>/dev/null | tail -n +2 | wc -l");
    int count = 0;
    try { count = countResult.output.strip().to!int; } catch (Exception e) {}

    if (count == 0)
    {
        result.message = "No coredumps";
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = format("%d coredump(s) found", count);
        result.status = "warn";
        result.priority = Priority.medium;
    }

    return result;
}

/// Check journal size
DiagResult checkLogs()
{
    DiagResult result;
    result.name = "Journal Size";

    auto journalResult = executeShell("journalctl --disk-usage 2>/dev/null");
    if (journalResult.status == 0)
    {
        // Extract size from output like "Archived and active journals take up 1.2G"
        auto match = journalResult.output.strip();
        result.message = match;
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = "Unable to check journal";
        result.status = "info";
        result.priority = Priority.low;
    }

    return result;
}

/// Check GPU status
DiagResult checkGPU()
{
    DiagResult result;
    result.name = "GPU Status";

    // Check NVIDIA first
    auto nvidiaResult = executeShell("nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null");
    if (nvidiaResult.status == 0 && nvidiaResult.output.strip().length > 0)
    {
        result.message = "NVIDIA: " ~ nvidiaResult.output.strip().split("\n")[0];
        result.status = "ok";
        result.priority = Priority.info;
        return result;
    }

    // Fallback to lspci
    auto pciResult = executeShell("lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1");
    if (pciResult.output.strip().length > 0)
    {
        result.message = pciResult.output.strip();
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = "No GPU detected";
        result.status = "info";
        result.priority = Priority.low;
    }

    return result;
}

/// Check network status
DiagResult checkNetwork()
{
    DiagResult result;
    result.name = "Network Interfaces";

    auto netResult = executeShell("ip -br addr 2>/dev/null | grep -v 'lo' | wc -l");
    int interfaces = 0;
    try { interfaces = netResult.output.strip().to!int; } catch (Exception e) {}

    if (interfaces > 0)
    {
        result.message = format("%d active interface(s)", interfaces);
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = "No network interfaces detected";
        result.status = "warn";
        result.priority = Priority.high;
    }

    return result;
}

/// Check package manager status
DiagResult checkPackages()
{
    DiagResult result;
    result.name = "Package Status";

    // Check rpm-ostree for Fedora Atomic
    auto ostreeResult = executeShell("rpm-ostree status 2>/dev/null | grep -c 'Version' || echo 0");
    int deployments = 0;
    try { deployments = ostreeResult.output.strip().to!int; } catch (Exception e) {}

    if (deployments > 0)
    {
        result.message = format("rpm-ostree: %d deployment(s)", deployments);
        result.status = "ok";
        result.priority = Priority.info;
        return result;
    }

    // Check Flatpak
    auto flatpakResult = executeShell("flatpak list 2>/dev/null | wc -l");
    int flatpaks = 0;
    try { flatpaks = flatpakResult.output.strip().to!int; } catch (Exception e) {}

    if (flatpaks > 0)
    {
        result.message = format("Flatpak: %d apps/runtimes", flatpaks);
        result.status = "ok";
        result.priority = Priority.info;
    }
    else
    {
        result.message = "No package info available";
        result.status = "info";
        result.priority = Priority.low;
    }

    return result;
}

/// Run full diagnostics scan
ScanEnvelope scanDiagnostics()
{
    auto envelope = ScanEnvelope.create("diagnostics");

    writeln("=== System Diagnostics ===");
    writeln("");

    DiagResult[] allResults;

    // Collect all diagnostic results
    allResults ~= detectOS();
    allResults ~= detectArch();
    allResults ~= detectECC();
    allResults ~= checkMemory();
    allResults ~= checkDiskHealth();
    allResults ~= checkBoot();
    allResults ~= checkServices();
    allResults ~= checkCoredumps();
    allResults ~= checkLogs();
    allResults ~= checkGPU();
    allResults ~= checkNetwork();
    allResults ~= checkPackages();

    // Convert to Evidence and display
    foreach (diag; allResults)
    {
        string icon = diag.status == "ok" ? "✓" :
                      diag.status == "warn" ? "⚠" :
                      diag.status == "error" ? "✗" : "ℹ";

        writefln("  [%s] %s: %s", icon, diag.name, diag.message);

        auto e = Evidence.create("diagnostic", diag.name.toLower().replace(" ", "-"));
        e.currentValue = diag.message;
        e.priority = diag.priority;
        e.description = format("%s: %s", diag.name, diag.message);
        e.metadata["status"] = diag.status;

        envelope.evidence ~= e;
    }

    writeln("");
    writeln("=== Diagnostics Complete ===");

    return envelope;
}

/// Generate plan from diagnostics (mainly for info, some actionable items)
Plan planDiagnostics(ScanEnvelope scan)
{
    auto plan = Plan.create("diagnostics", "Address diagnostic findings");
    plan.evidence = scan.evidence;

    writeln("");
    writeln("=== Diagnostic Recommendations ===");
    writeln("");

    int actionable = 0;

    foreach (e; scan.evidence)
    {
        string status = e.metadata.get("status", "info");

        if (status == "warn" || status == "error")
        {
            // Create actionable step based on finding
            if (e.category.canFind("failed-service") || e.description.canFind("failed"))
            {
                auto step = Step.create("check-" ~ e.category, "Investigate " ~ e.description);
                step.command = "systemctl --failed --no-pager";
                step.preview = "Show failed services";
                step.reversibility = Reversibility.full;
                step.requiresElevation = false;
                plan.steps ~= step;
                actionable++;
            }
            else if (e.category.canFind("coredump") || e.description.canFind("coredump"))
            {
                auto step = Step.create("check-" ~ e.category, "Review recent crashes");
                step.command = "coredumpctl list | tail -10";
                step.preview = "List recent coredumps";
                step.reversibility = Reversibility.full;
                step.requiresElevation = false;
                plan.steps ~= step;
                actionable++;
            }
        }
    }

    if (actionable > 0)
    {
        writefln("Generated %d actionable steps", actionable);
    }
    else
    {
        writeln("No actionable items - system appears healthy");
    }

    return plan;
}
