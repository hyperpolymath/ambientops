// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// System pack - system optimization with plan-first approach

module packs.system;

import core.types;
import std.stdio;
import std.process;
import std.file;
import std.path;
import std.string;
import std.datetime;

/// Scan system state and collect evidence
ScanEnvelope scanSystem()
{
    auto envelope = ScanEnvelope.create("system");

    writeln("=== Scanning System State ===");
    writeln("");

    // Check nouveau driver status
    {
        auto e = Evidence.create("driver", "NVIDIA nouveau driver status");
        auto result = executeShell("lsmod | grep -q nouveau && echo 'loaded' || echo 'not-loaded'");
        e.currentValue = result.output.strip();
        e.expectedValue = "not-loaded";
        e.priority = e.currentValue == "loaded" ? Priority.high : Priority.info;
        e.description = e.currentValue == "loaded"
            ? "Nouveau driver is loaded (may conflict with NVIDIA)"
            : "Nouveau driver not loaded (good)";
        envelope.evidence ~= e;
        writefln("  [%s] %s", e.priority, e.description);
    }

    // Check firewall status
    {
        auto e = Evidence.create("firewall", "Firewall port configuration");
        auto result = executeShell("firewall-cmd --list-ports 2>/dev/null || echo 'unavailable'");
        e.currentValue = result.output.strip();
        e.priority = Priority.medium;
        e.description = "Current open ports: " ~ (e.currentValue.length > 0 ? e.currentValue : "none");
        envelope.evidence ~= e;
        writefln("  [%s] %s", e.priority, e.description);
    }

    // Check journal size
    {
        auto e = Evidence.create("disk", "Journal log size");
        auto result = executeShell("journalctl --disk-usage 2>/dev/null | grep -oP '[0-9.]+[GMK]' || echo 'unknown'");
        e.currentValue = result.output.strip();
        e.priority = Priority.low;
        e.description = "Journal size: " ~ e.currentValue;
        envelope.evidence ~= e;
        writefln("  [%s] %s", e.priority, e.description);
    }

    // Check TCP congestion control
    {
        auto e = Evidence.create("network", "TCP congestion control algorithm");
        auto result = executeShell("sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 'unknown'");
        e.currentValue = result.output.strip();
        e.expectedValue = "bbr";
        e.priority = e.currentValue != "bbr" ? Priority.low : Priority.info;
        e.description = "TCP congestion: " ~ e.currentValue ~ (e.currentValue != "bbr" ? " (bbr recommended)" : " (optimal)");
        envelope.evidence ~= e;
        writefln("  [%s] %s", e.priority, e.description);
    }

    // Check ModemManager status
    {
        auto e = Evidence.create("service", "ModemManager service status");
        auto result = executeShell("systemctl is-enabled ModemManager 2>/dev/null || echo 'not-found'");
        e.currentValue = result.output.strip();
        e.expectedValue = "disabled";
        e.priority = e.currentValue == "enabled" ? Priority.low : Priority.info;
        e.description = "ModemManager: " ~ e.currentValue ~ (e.currentValue == "enabled" ? " (usually unnecessary)" : "");
        envelope.evidence ~= e;
        writefln("  [%s] %s", e.priority, e.description);
    }

    writeln("");
    writefln("Scan complete: %d items collected", envelope.evidence.length);

    return envelope;
}

/// Generate optimization plan based on evidence
Plan planSystemOptimization(ScanEnvelope scan)
{
    auto plan = Plan.create("system-optimization", "System optimization based on scan results");
    plan.evidence = scan.evidence;

    writeln("");
    writeln("=== Generating Optimization Plan ===");
    writeln("");

    foreach (e; scan.evidence)
    {
        // Only create steps for things that need fixing
        if (e.expectedValue.length > 0 && e.currentValue != e.expectedValue)
        {
            Step step;

            if (e.category == "driver" && e.currentValue == "loaded")
            {
                step = Step.create("blacklist-nouveau", "Blacklist nouveau driver for NVIDIA");
                step.command = "rpm-ostree kargs --append=modprobe.blacklist=nouveau --append=rd.driver.blacklist=nouveau";
                step.preview = "Add kernel arguments to blacklist nouveau";
                step.reversibility = Reversibility.full;
                step.undoCommand = "rpm-ostree kargs --delete=modprobe.blacklist=nouveau --delete=rd.driver.blacklist=nouveau";
                step.requiresElevation = true;
                step.metadata["reboot_required"] = "true";
                plan.steps ~= step;
            }

            if (e.category == "network" && e.currentValue != "bbr")
            {
                step = Step.create("enable-bbr", "Enable BBR TCP congestion control");
                step.command = `echo -e "net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr" | sudo tee /etc/sysctl.d/99-bbr.conf && sudo sysctl -p /etc/sysctl.d/99-bbr.conf`;
                step.preview = "Create sysctl config for BBR";
                step.reversibility = Reversibility.full;
                step.undoCommand = "sudo rm /etc/sysctl.d/99-bbr.conf && sudo sysctl -p";
                step.requiresElevation = true;
                plan.steps ~= step;
            }

            if (e.category == "service" && e.currentValue == "enabled")
            {
                step = Step.create("disable-modemmanager", "Disable ModemManager service");
                step.command = "sudo systemctl disable --now ModemManager";
                step.preview = "Stop and disable ModemManager";
                step.reversibility = Reversibility.full;
                step.undoCommand = "sudo systemctl enable --now ModemManager";
                step.requiresElevation = true;
                plan.steps ~= step;
            }
        }
    }

    // Always offer firewall configuration
    {
        auto step = Step.create("configure-firewall", "Configure firewall for Syncthing + KDE Connect");
        step.command = "firewall-cmd --permanent --add-port=22000/tcp --add-port=22000/udp --add-port=21027/udp --add-port=1716/tcp --add-port=1716/udp && firewall-cmd --reload";
        step.preview = "Open ports: 22000/tcp+udp (Syncthing), 21027/udp (Syncthing local), 1716/tcp+udp (KDE Connect)";
        step.reversibility = Reversibility.full;
        step.undoCommand = "firewall-cmd --permanent --remove-port=22000/tcp --remove-port=22000/udp --remove-port=21027/udp --remove-port=1716/tcp --remove-port=1716/udp && firewall-cmd --reload";
        step.requiresElevation = true;
        plan.steps ~= step;
    }

    // Journal vacuum step
    {
        auto step = Step.create("vacuum-journal", "Vacuum journal logs to 500MB");
        step.command = "sudo journalctl --vacuum-size=500M";
        step.preview = "Reduce journal log size to max 500MB";
        step.reversibility = Reversibility.none; // Cannot un-delete logs
        step.requiresElevation = true;
        plan.steps ~= step;
    }

    writefln("Plan generated: %d steps", plan.steps.length);

    return plan;
}

/// Approve the plan (mark it ready for execution)
Plan approvePlan(Plan plan)
{
    plan.approved = true;
    plan.approvedBy = "user";
    return plan;
}
