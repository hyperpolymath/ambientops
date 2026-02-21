/**
 * diagnostics.d - Core Diagnostics Module for Juisys Technical Add-on
 *
 * Privacy-first system diagnostics similar to SIW (System Information for Windows)
 * but for macOS and aimed at developers/technical users.
 *
 * Key Features:
 * - Comprehensive hardware information
 * - Software & process diagnostics
 * - Network diagnostics
 * - Performance metrics
 * - Security auditing
 * - Developer-focused technical data
 *
 * PRIVACY GUARANTEES:
 * - 100% local processing (no network calls)
 * - Ephemeral data only (cleared after session)
 * - Explicit consent required via Juisys security module
 * - No personal data collection
 * - Optional activation (opt-in)
 *
 * Author: Claude Sonnet 4.5 (Anthropic)
 * License: MIT
 * Language: D (dlang.org)
 * Integration: Juisys Julia project via C FFI
 */

module diagnostics.core;

import std.stdio;
import std.process;
import std.string;
import std.conv;
import std.datetime;
import std.file;
import std.json;
import std.algorithm;
import std.range;

/**
 * DiagnosticLevel - Scope of diagnostics to perform
 */
enum DiagnosticLevel {
    BASIC,       // Essential system info only
    STANDARD,    // Common diagnostics for developers
    DEEP,        // Comprehensive technical analysis
    FORENSIC     // Maximum detail (performance intensive)
}

/**
 * DiagnosticCategory - Types of diagnostic information
 */
enum DiagnosticCategory {
    HARDWARE,
    SOFTWARE,
    NETWORK,
    PERFORMANCE,
    SECURITY,
    STORAGE,
    MEMORY,
    CPU,
    GPU,
    PROCESSES,
    SERVICES,
    ENVIRONMENT,
    KERNEL,
    FILESYSTEM
}

/**
 * DiagnosticResult - Container for diagnostic data
 */
struct DiagnosticResult {
    DiagnosticCategory category;
    string name;
    JSONValue data;
    SysTime timestamp;
    DiagnosticLevel level;
    bool sensitive;  // Contains potentially sensitive data
}

/**
 * SystemDiagnostics - Main diagnostics engine
 */
class SystemDiagnostics {
    private DiagnosticLevel level;
    private bool consentGranted;
    private DiagnosticResult[] results;

    this(DiagnosticLevel level = DiagnosticLevel.STANDARD) {
        this.level = level;
        this.consentGranted = false;
        this.results = [];
    }

    /**
     * Request consent for diagnostics (integrates with Juisys Security module)
     */
    bool requestConsent() {
        writeln("="~repeat("=", 69));
        writeln("DIAGNOSTICS CONSENT REQUEST (GDPR Article 6.1.a)");
        writeln("="~repeat("=", 69));
        writeln("Juisys Diagnostics Add-on requests permission to:");
        writeln();
        writeln("  Operation: Collect system diagnostic information");
        writeln("  Purpose:   Technical analysis and troubleshooting");
        writeln("  Level:     ", level);
        writeln("  Data:      Ephemeral (cleared after session)");
        writeln("  Privacy:   100% local, no network transmission");
        writeln();
        writeln("This will collect technical information including:");
        writeln("  - Hardware specifications");
        writeln("  - Software/process lists");
        writeln("  - Network configuration (no traffic/credentials)");
        writeln("  - Performance metrics");
        writeln("  - System configuration");
        writeln();
        writeln("NOTE: Developer-focused diagnostics may include:");
        writeln("  - Process memory usage");
        writeln("  - Kernel parameters");
        writeln("  - Environment variables (filtered for secrets)");
        writeln("  - File system details");
        writeln();
        writeln("="~repeat("=", 69));
        write("Grant consent? [y/N]: ");
        stdout.flush();

        string response = readln().strip().toLower();
        consentGranted = (response == "y" || response == "yes");

        if (consentGranted) {
            writeln("✓ Consent granted for diagnostics");
        } else {
            writeln("✗ Consent denied - diagnostics disabled");
        }

        return consentGranted;
    }

    /**
     * Run all diagnostics based on level
     */
    DiagnosticResult[] runDiagnostics() {
        if (!consentGranted) {
            writeln("ERROR: Consent required before running diagnostics");
            return [];
        }

        writeln("\nRunning diagnostics (Level: ", level, ")...\n");

        results = [];

        // Basic diagnostics (all levels)
        collectHardwareInfo();
        collectSoftwareInfo();
        collectStorageInfo();

        // Standard and above
        if (level >= DiagnosticLevel.STANDARD) {
            collectNetworkInfo();
            collectProcessInfo();
            collectPerformanceMetrics();
        }

        // Deep and above
        if (level >= DiagnosticLevel.DEEP) {
            collectMemoryDetails();
            collectCPUDetails();
            collectKernelInfo();
            collectEnvironmentInfo();
        }

        // Forensic level
        if (level >= DiagnosticLevel.FORENSIC) {
            collectFileSystemDetails();
            collectSecurityInfo();
            collectServiceDetails();
        }

        writeln("✓ Diagnostics complete: ", results.length, " data points collected\n");

        return results;
    }

    /**
     * HARDWARE DIAGNOSTICS
     */
    private void collectHardwareInfo() {
        writeln("  Collecting hardware information...");

        JSONValue hwData = JSONValue.emptyObject();

        // System profiler data (macOS)
        try {
            // CPU Information
            auto cpuInfo = executeShell("sysctl -n machdep.cpu.brand_string");
            if (cpuInfo.status == 0) {
                hwData["cpu_model"] = cpuInfo.output.strip();
            }

            auto cpuCores = executeShell("sysctl -n hw.ncpu");
            if (cpuCores.status == 0) {
                hwData["cpu_cores"] = cpuCores.output.strip().to!int;
            }

            auto cpuPhysical = executeShell("sysctl -n hw.physicalcpu");
            if (cpuPhysical.status == 0) {
                hwData["cpu_physical_cores"] = cpuPhysical.output.strip().to!int;
            }

            // Memory
            auto memSize = executeShell("sysctl -n hw.memsize");
            if (memSize.status == 0) {
                long memBytes = memSize.output.strip().to!long;
                hwData["memory_bytes"] = memBytes;
                hwData["memory_gb"] = memBytes / (1024.0 * 1024.0 * 1024.0);
            }

            // Machine model
            auto model = executeShell("sysctl -n hw.model");
            if (model.status == 0) {
                hwData["machine_model"] = model.output.strip();
            }

            // Architecture
            auto arch = executeShell("uname -m");
            if (arch.status == 0) {
                hwData["architecture"] = arch.output.strip();
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.HARDWARE,
                "system_hardware",
                hwData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Some hardware info unavailable: ", e.msg);
        }
    }

    /**
     * SOFTWARE DIAGNOSTICS
     */
    private void collectSoftwareInfo() {
        writeln("  Collecting software information...");

        JSONValue swData = JSONValue.emptyObject();

        try {
            // OS Version
            auto osVersion = executeShell("sw_vers -productVersion");
            if (osVersion.status == 0) {
                swData["os_version"] = osVersion.output.strip();
            }

            auto osBuild = executeShell("sw_vers -buildVersion");
            if (osBuild.status == 0) {
                swData["os_build"] = osBuild.output.strip();
            }

            // Kernel
            auto kernel = executeShell("uname -r");
            if (kernel.status == 0) {
                swData["kernel_version"] = kernel.output.strip();
            }

            // Uptime
            auto uptime = executeShell("sysctl -n kern.boottime");
            if (uptime.status == 0) {
                swData["boot_time"] = uptime.output.strip();
            }

            // Shell
            auto shell = executeShell("echo $SHELL");
            if (shell.status == 0) {
                swData["default_shell"] = shell.output.strip();
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.SOFTWARE,
                "system_software",
                swData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Some software info unavailable: ", e.msg);
        }
    }

    /**
     * STORAGE DIAGNOSTICS
     */
    private void collectStorageInfo() {
        writeln("  Collecting storage information...");

        JSONValue storageData = JSONValue.emptyArray();

        try {
            // Disk usage
            auto diskInfo = executeShell("df -h");
            if (diskInfo.status == 0) {
                auto lines = diskInfo.output.split("\n");

                foreach (line; lines[1..$]) {  // Skip header
                    if (line.strip().length > 0) {
                        auto parts = line.split();
                        if (parts.length >= 6) {
                            JSONValue disk = JSONValue.emptyObject();
                            disk["filesystem"] = parts[0];
                            disk["size"] = parts[1];
                            disk["used"] = parts[2];
                            disk["available"] = parts[3];
                            disk["capacity"] = parts[4];
                            disk["mounted_on"] = parts[5];
                            storageData.array ~= disk;
                        }
                    }
                }
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.STORAGE,
                "disk_usage",
                storageData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Storage info unavailable: ", e.msg);
        }
    }

    /**
     * NETWORK DIAGNOSTICS
     */
    private void collectNetworkInfo() {
        writeln("  Collecting network information...");

        JSONValue netData = JSONValue.emptyObject();

        try {
            // Network interfaces
            auto ifconfig = executeShell("ifconfig");
            if (ifconfig.status == 0) {
                netData["interfaces_raw"] = ifconfig.output;
            }

            // Active connections (count only for privacy)
            auto netstat = executeShell("netstat -an | grep ESTABLISHED | wc -l");
            if (netstat.status == 0) {
                netData["active_connections"] = netstat.output.strip().to!int;
            }

            // Routing table
            auto route = executeShell("netstat -rn");
            if (route.status == 0) {
                netData["routing_table"] = route.output;
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.NETWORK,
                "network_config",
                netData,
                Clock.currTime(),
                level,
                false  // No credentials/traffic data
            );

        } catch (Exception e) {
            writeln("    Warning: Network info unavailable: ", e.msg);
        }
    }

    /**
     * PROCESS DIAGNOSTICS
     */
    private void collectProcessInfo() {
        writeln("  Collecting process information...");

        JSONValue procData = JSONValue.emptyObject();

        try {
            // Process count
            auto psCount = executeShell("ps aux | wc -l");
            if (psCount.status == 0) {
                procData["total_processes"] = psCount.output.strip().to!int;
            }

            // Top processes by CPU
            auto topCPU = executeShell("ps aux | sort -rk 3 | head -10");
            if (topCPU.status == 0) {
                procData["top_cpu_processes"] = topCPU.output;
            }

            // Top processes by memory
            auto topMem = executeShell("ps aux | sort -rk 4 | head -10");
            if (topMem.status == 0) {
                procData["top_memory_processes"] = topMem.output;
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.PROCESSES,
                "process_info",
                procData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Process info unavailable: ", e.msg);
        }
    }

    /**
     * PERFORMANCE DIAGNOSTICS
     */
    private void collectPerformanceMetrics() {
        writeln("  Collecting performance metrics...");

        JSONValue perfData = JSONValue.emptyObject();

        try {
            // Load average
            auto load = executeShell("sysctl -n vm.loadavg");
            if (load.status == 0) {
                perfData["load_average"] = load.output.strip();
            }

            // CPU usage
            auto cpuUsage = executeShell("top -l 1 | grep 'CPU usage'");
            if (cpuUsage.status == 0) {
                perfData["cpu_usage"] = cpuUsage.output.strip();
            }

            // Memory pressure
            auto memPressure = executeShell("sysctl -n vm.memory_pressure");
            if (memPressure.status == 0) {
                perfData["memory_pressure"] = memPressure.output.strip();
            }

            // Swap usage
            auto swapUsage = executeShell("sysctl -n vm.swapusage");
            if (swapUsage.status == 0) {
                perfData["swap_usage"] = swapUsage.output.strip();
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.PERFORMANCE,
                "performance_metrics",
                perfData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Performance metrics unavailable: ", e.msg);
        }
    }

    /**
     * DEEP DIAGNOSTICS - Memory Details
     */
    private void collectMemoryDetails() {
        writeln("  Collecting detailed memory information...");

        JSONValue memData = JSONValue.emptyObject();

        try {
            // VM statistics
            auto vmStat = executeShell("vm_stat");
            if (vmStat.status == 0) {
                memData["vm_statistics"] = vmStat.output;
            }

            // Memory regions
            auto memRegions = executeShell("sysctl -a | grep '^vm\\.'");
            if (memRegions.status == 0) {
                memData["vm_parameters"] = memRegions.output;
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.MEMORY,
                "memory_details",
                memData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Memory details unavailable: ", e.msg);
        }
    }

    /**
     * DEEP DIAGNOSTICS - CPU Details
     */
    private void collectCPUDetails() {
        writeln("  Collecting detailed CPU information...");

        JSONValue cpuData = JSONValue.emptyObject();

        try {
            // All CPU-related sysctls
            auto cpuParams = executeShell("sysctl -a | grep '^machdep\\.cpu\\.'");
            if (cpuParams.status == 0) {
                cpuData["cpu_parameters"] = cpuParams.output;
            }

            // CPU features
            auto cpuFeatures = executeShell("sysctl -n machdep.cpu.features");
            if (cpuFeatures.status == 0) {
                cpuData["cpu_features"] = cpuFeatures.output.strip();
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.CPU,
                "cpu_details",
                cpuData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: CPU details unavailable: ", e.msg);
        }
    }

    /**
     * DEEP DIAGNOSTICS - Kernel Info
     */
    private void collectKernelInfo() {
        writeln("  Collecting kernel information...");

        JSONValue kernelData = JSONValue.emptyObject();

        try {
            // Kernel parameters
            auto kernParams = executeShell("sysctl -a | grep '^kern\\.'");
            if (kernParams.status == 0) {
                kernelData["kernel_parameters"] = kernParams.output;
            }

            // Kernel modules (if accessible)
            auto kextstat = executeShell("kextstat");
            if (kextstat.status == 0) {
                kernelData["loaded_extensions"] = kextstat.output;
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.KERNEL,
                "kernel_info",
                kernelData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Kernel info unavailable: ", e.msg);
        }
    }

    /**
     * DEEP DIAGNOSTICS - Environment Info
     * PRIVACY: Filters out potentially sensitive variables
     */
    private void collectEnvironmentInfo() {
        writeln("  Collecting environment information (filtered)...");

        JSONValue envData = JSONValue.emptyObject();

        try {
            // Get environment variables, filter sensitive ones
            string[] safePrefixes = [
                "LANG", "LC_", "PATH", "HOME", "USER", "SHELL",
                "TERM", "EDITOR", "DISPLAY"
            ];

            auto env = executeShell("env");
            if (env.status == 0) {
                auto lines = env.output.split("\n");
                JSONValue filtered = JSONValue.emptyObject();

                foreach (line; lines) {
                    if (line.indexOf("=") > 0) {
                        auto key = line.split("=")[0];

                        // Only include non-sensitive variables
                        bool safe = false;
                        foreach (prefix; safePrefixes) {
                            if (key.startsWith(prefix)) {
                                safe = true;
                                break;
                            }
                        }

                        if (safe) {
                            filtered[key] = line.split("=", 2)[1];
                        }
                    }
                }

                envData["filtered_environment"] = filtered;
                envData["total_variables"] = lines.length;
                envData["filtered_count"] = filtered.object.length;
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.ENVIRONMENT,
                "environment_info",
                envData,
                Clock.currTime(),
                level,
                true  // Mark as potentially sensitive
            );

        } catch (Exception e) {
            writeln("    Warning: Environment info unavailable: ", e.msg);
        }
    }

    /**
     * FORENSIC DIAGNOSTICS - Filesystem Details
     */
    private void collectFileSystemDetails() {
        writeln("  Collecting filesystem details...");

        JSONValue fsData = JSONValue.emptyObject();

        try {
            // Filesystem types
            auto mount = executeShell("mount");
            if (mount.status == 0) {
                fsData["mounted_filesystems"] = mount.output;
            }

            // Inode usage
            auto inodes = executeShell("df -i");
            if (inodes.status == 0) {
                fsData["inode_usage"] = inodes.output;
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.FILESYSTEM,
                "filesystem_details",
                fsData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Filesystem details unavailable: ", e.msg);
        }
    }

    /**
     * FORENSIC DIAGNOSTICS - Security Info
     */
    private void collectSecurityInfo() {
        writeln("  Collecting security information...");

        JSONValue secData = JSONValue.emptyObject();

        try {
            // Firewall status
            auto firewall = executeShell("sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate");
            if (firewall.status == 0) {
                secData["firewall_status"] = firewall.output.strip();
            }

            // SIP status (System Integrity Protection)
            auto sip = executeShell("csrutil status");
            if (sip.status == 0) {
                secData["sip_status"] = sip.output.strip();
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.SECURITY,
                "security_info",
                secData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Security info unavailable: ", e.msg);
        }
    }

    /**
     * FORENSIC DIAGNOSTICS - Service Details
     */
    private void collectServiceDetails() {
        writeln("  Collecting service/daemon information...");

        JSONValue svcData = JSONValue.emptyObject();

        try {
            // LaunchDaemons and LaunchAgents
            auto launchctl = executeShell("launchctl list");
            if (launchctl.status == 0) {
                svcData["launchctl_services"] = launchctl.output;
            }

            results ~= DiagnosticResult(
                DiagnosticCategory.SERVICES,
                "service_details",
                svcData,
                Clock.currTime(),
                level,
                false
            );

        } catch (Exception e) {
            writeln("    Warning: Service details unavailable: ", e.msg);
        }
    }

    /**
     * Export diagnostics to JSON
     */
    JSONValue exportJSON() {
        JSONValue export_ = JSONValue.emptyObject();
        export_["timestamp"] = Clock.currTime().toISOExtString();
        export_["level"] = level.to!string;
        export_["privacy_notice"] = "100% local processing, ephemeral data";

        JSONValue resultsArray = JSONValue.emptyArray();
        foreach (result; results) {
            JSONValue r = JSONValue.emptyObject();
            r["category"] = result.category.to!string;
            r["name"] = result.name;
            r["data"] = result.data;
            r["timestamp"] = result.timestamp.toISOExtString();
            r["sensitive"] = result.sensitive;
            resultsArray.array ~= r;
        }

        export_["results"] = resultsArray;
        export_["total_diagnostics"] = results.length;

        return export_;
    }

    /**
     * Clear all diagnostic data (GDPR Erasure)
     */
    void clearData() {
        results = [];
        writeln("✓ Diagnostic data cleared (GDPR Article 17)");
    }
}

/**
 * C FFI exports for Julia integration
 */
extern(C) {
    export void* createDiagnostics(int level) {
        return cast(void*) new SystemDiagnostics(cast(DiagnosticLevel)level);
    }

    export bool requestDiagnosticsConsent(void* diag) {
        auto d = cast(SystemDiagnostics)diag;
        return d.requestConsent();
    }

    export void runDiagnostics(void* diag) {
        auto d = cast(SystemDiagnostics)diag;
        d.runDiagnostics();
    }

    export const(char)* exportDiagnosticsJSON(void* diag) {
        auto d = cast(SystemDiagnostics)diag;
        return d.exportJSON().toString().toStringz();
    }

    export void clearDiagnosticsData(void* diag) {
        auto d = cast(SystemDiagnostics)diag;
        d.clearData();
    }

    export void destroyDiagnostics(void* diag) {
        auto d = cast(SystemDiagnostics)diag;
        destroy(d);
    }
}
