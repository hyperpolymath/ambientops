// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Hyperpolymath
//
// Security utilities - input validation, secure file handling

module core.security;

import std.stdio;
import std.file;
import std.path;
import std.string;
import std.regex;
import std.process;
import std.algorithm;

/// Characters that are dangerous in shell commands
enum SHELL_DANGEROUS = ['`', '$', '(', ')', '{', '}', ';', '&', '|', '<', '>', '\n', '\r', '\0'];

/// Validate and sanitize a path for use in commands
/// Returns null if path is suspicious
string sanitizePath(string path)
{
    if (path.length == 0)
        return null;

    // Reject paths with dangerous characters
    foreach (c; SHELL_DANGEROUS)
    {
        if (path.canFind(c))
            return null;
    }

    // Reject paths with ".." (path traversal)
    if (path.canFind(".."))
        return null;

    // Reject paths starting with -
    if (path.startsWith("-"))
        return null;

    // Normalize and return
    return path.strip();
}

/// Validate command does not contain injection
bool isCommandSafe(string cmd)
{
    // Check for obvious injection patterns
    auto dangerousPatterns = [
        regex(`\$\(`),          // Command substitution
        regex("`"),             // Backtick substitution
        regex(`\|\s*\w+`),      // Pipe to command
        regex(`;\s*\w+`),       // Command chaining
        regex(`&&\s*\w+`),      // AND chaining (allow in our commands but flag external)
        regex(`>\s*/`),         // Redirect to absolute path
        regex(`curl|wget|nc`),  // Network commands
    ];

    foreach (pattern; dangerousPatterns)
    {
        if (!matchFirst(cmd, pattern).empty)
            return false;
    }

    return true;
}

/// Set secure permissions on run bundle directory
void secureRunBundle(string path)
{
    if (!exists(path))
        mkdirRecurse(path);

    // Set 700 permissions (owner only)
    auto result = executeShell("chmod 700 " ~ path);
    if (result.status != 0)
    {
        stderr.writefln("Warning: Could not set permissions on %s", path);
    }
}

/// Set secure permissions on a file
void secureFile(string filepath)
{
    if (!exists(filepath))
        return;

    // Set 600 permissions (owner read/write only)
    auto result = executeShell("chmod 600 " ~ filepath);
    if (result.status != 0)
    {
        stderr.writefln("Warning: Could not set permissions on %s", filepath);
    }
}

/// Check if running as root (discouraged for most operations)
bool isRunningAsRoot()
{
    auto result = executeShell("id -u");
    return result.output.strip() == "0";
}

/// Validate that we're not running as root unless necessary
void warnIfRoot()
{
    if (isRunningAsRoot())
    {
        stderr.writeln("⚠ WARNING: Running as root is discouraged.");
        stderr.writeln("  Use 'sor' as a regular user. Sudo will be invoked only when needed.");
        stderr.writeln("");
    }
}

/// Generate a secure random ID (using system entropy)
string generateSecureId()
{
    import std.uuid : randomUUID;
    return randomUUID().toString();
}

/// Hash a string using SHA-256 (for integrity checks)
string sha256Hash(string input)
{
    import std.digest.sha : SHA256, toHexString;
    auto hash = SHA256();
    hash.put(cast(ubyte[]) input);
    return toHexString(hash.finish()).idup.toLower();
}

/// Verify integrity of a file against expected hash
bool verifyFileIntegrity(string filepath, string expectedHash)
{
    if (!exists(filepath))
        return false;

    auto content = cast(string) read(filepath);
    auto actualHash = sha256Hash(content);
    return actualHash == expectedHash.toLower();
}

/// Security audit result
struct SecurityAudit
{
    bool runBundleSecure;
    bool notRoot;
    string[] warnings;
}

/// Perform security audit
SecurityAudit performSecurityAudit(string runBundlePath)
{
    SecurityAudit audit;

    // Check run bundle permissions
    if (exists(runBundlePath))
    {
        auto result = executeShell("stat -c '%a' " ~ runBundlePath ~ " 2>/dev/null");
        audit.runBundleSecure = result.output.strip() == "700";
        if (!audit.runBundleSecure)
            audit.warnings ~= "Run bundle directory has insecure permissions";
    }
    else
    {
        audit.runBundleSecure = true; // Will be created with secure permissions
    }

    // Check if running as root
    audit.notRoot = !isRunningAsRoot();
    if (!audit.notRoot)
        audit.warnings ~= "Running as root is discouraged";

    return audit;
}
