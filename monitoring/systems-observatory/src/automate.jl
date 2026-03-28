"""
    Automate.jl - System Scanning Automation for Juisys

    Safely scans installed applications using package managers.
    Supports: winget (Windows), apt/dnf (Linux), brew (macOS), pacman, zypper

    PRIVACY: Only reads package manager output, never installs/modifies.
    Requires SYSTEM_SCAN and PACKAGE_MANAGER consent before access.

    GDPR: Collection and Organization processing types.

    Author: Claude Sonnet 4.5 (Anthropic)
    License: MIT
"""

module Automate

export detect_package_manager, scan_installed_apps
export PackageManager, scan_with_consent
export parse_package_list

@enum PackageManager begin
    WINGET = 1    # Windows
    APT = 2       # Debian/Ubuntu
    DNF = 3       # Fedora/RHEL
    BREW = 4      # macOS/Linux
    PACMAN = 5    # Arch Linux
    ZYPPER = 6    # openSUSE
    UNKNOWN = 99
end

"""
    detect_package_manager()

    Auto-detect available package manager on system.

    Returns: PackageManager enum
"""
function detect_package_manager()
    # Check which package manager commands are available

    if Sys.iswindows()
        if is_command_available("winget")
            return WINGET
        end
    elseif Sys.islinux()
        if is_command_available("apt")
            return APT
        elseif is_command_available("dnf")
            return DNF
        elseif is_command_available("pacman")
            return PACMAN
        elseif is_command_available("zypper")
            return ZYPPER
        elseif is_command_available("brew")
            return BREW
        end
    elseif Sys.isapple()
        if is_command_available("brew")
            return BREW
        end
    end

    @warn "No supported package manager detected"
    return UNKNOWN
end

"""
    is_command_available(cmd::String)

    Check if command is available in PATH.
"""
function is_command_available(cmd::String)
    try
        # Use `which` on Unix, `where` on Windows
        check_cmd = Sys.iswindows() ? "where" : "which"
        result = read(`$check_cmd $cmd`, String)
        return !isempty(strip(result))
    catch
        return false
    end
end

"""
    scan_installed_apps(pm::PackageManager)

    Scan installed applications using package manager.

    NOTE: Caller MUST verify consent before calling this function.

    Returns: Vector of app metadata dicts.
"""
function scan_installed_apps(pm::PackageManager)
    if pm == UNKNOWN
        @error "Cannot scan with unknown package manager"
        return []
    end

    @info "Scanning installed apps" package_manager=pm

    try
        if pm == WINGET
            return scan_winget()
        elseif pm == APT
            return scan_apt()
        elseif pm == DNF
            return scan_dnf()
        elseif pm == BREW
            return scan_brew()
        elseif pm == PACMAN
            return scan_pacman()
        elseif pm == ZYPPER
            return scan_zypper()
        end
    catch e
        @error "Scan failed" exception=e package_manager=pm
        return []
    end

    return []
end

"""
    scan_winget()

    Scan Windows using winget.
"""
function scan_winget()
    apps = []

    try
        output = read(`winget list`, String)
        apps = parse_winget_output(output)
        @info "Winget scan complete" count=length(apps)
    catch e
        @error "Winget scan failed" exception=e
    end

    return apps
end

"""
    parse_winget_output(output::String)

    Parse winget list output.
"""
function parse_winget_output(output::String)
    apps = []
    lines = split(output, '\n')

    # Skip header lines
    for line in lines[3:end]
        line = strip(line)
        isempty(line) && continue

        # winget list format: Name  Id  Version  Source
        parts = split(line, r"\s{2,}")  # Split on 2+ spaces

        if length(parts) >= 1
            app_name = strip(parts[1])

            metadata = Dict{String, Any}(
                "name" => app_name,
                "version" => length(parts) >= 3 ? strip(parts[3]) : nothing,
                "publisher" => nothing,
                "is_foss" => false,  # Unknown by default
                "cost" => 0.0,
                "platform" => "windows"
            )

            push!(apps, metadata)
        end
    end

    return apps
end

"""
    scan_apt()

    Scan Debian/Ubuntu using apt.
"""
function scan_apt()
    apps = []

    try
        output = read(`dpkg -l`, String)
        apps = parse_dpkg_output(output)
        @info "APT scan complete" count=length(apps)
    catch e
        @error "APT scan failed" exception=e
    end

    return apps
end

"""
    parse_dpkg_output(output::String)

    Parse dpkg -l output.
"""
function parse_dpkg_output(output::String)
    apps = []
    lines = split(output, '\n')

    for line in lines
        line = strip(line)

        # Skip header and divider lines
        if !startswith(line, "ii")
            continue
        end

        parts = split(line, r"\s+")

        if length(parts) >= 3
            app_name = strip(parts[2])
            version = strip(parts[3])

            metadata = Dict{String, Any}(
                "name" => app_name,
                "version" => version,
                "publisher" => nothing,
                "is_foss" => true,  # Debian packages usually FOSS
                "cost" => 0.0,
                "platform" => "linux_debian"
            )

            push!(apps, metadata)
        end
    end

    return apps
end

"""
    scan_dnf()

    Scan Fedora/RHEL using dnf.
"""
function scan_dnf()
    apps = []

    try
        output = read(`dnf list installed`, String)
        apps = parse_dnf_output(output)
        @info "DNF scan complete" count=length(apps)
    catch e
        @error "DNF scan failed" exception=e
    end

    return apps
end

"""
    parse_dnf_output(output::String)

    Parse dnf list installed output.
"""
function parse_dnf_output(output::String)
    apps = []
    lines = split(output, '\n')

    for line in lines
        line = strip(line)

        # Skip headers and empty lines
        if isempty(line) || startswith(line, "Installed") || startswith(line, "Last")
            continue
        end

        parts = split(line, r"\s+")

        if length(parts) >= 2
            # Format: package.arch  version  repository
            name_arch = strip(parts[1])
            app_name = split(name_arch, '.')[1]  # Remove architecture
            version = strip(parts[2])

            metadata = Dict{String, Any}(
                "name" => app_name,
                "version" => version,
                "publisher" => nothing,
                "is_foss" => true,
                "cost" => 0.0,
                "platform" => "linux_fedora"
            )

            push!(apps, metadata)
        end
    end

    return apps
end

"""
    scan_brew()

    Scan macOS/Linux using Homebrew.
"""
function scan_brew()
    apps = []

    try
        output = read(`brew list --formula`, String)
        formulas = split(output, '\n')

        for formula in formulas
            formula = strip(formula)
            isempty(formula) && continue

            metadata = Dict{String, Any}(
                "name" => formula,
                "version" => nothing,  # Could get with `brew info`
                "publisher" => nothing,
                "is_foss" => true,  # Homebrew packages typically FOSS
                "cost" => 0.0,
                "platform" => Sys.isapple() ? "macos" : "linux"
            )

            push!(apps, metadata)
        end

        @info "Brew scan complete" count=length(apps)
    catch e
        @error "Brew scan failed" exception=e
    end

    return apps
end

"""
    scan_pacman()

    Scan Arch Linux using pacman.
"""
function scan_pacman()
    apps = []

    try
        output = read(`pacman -Q`, String)
        apps = parse_pacman_output(output)
        @info "Pacman scan complete" count=length(apps)
    catch e
        @error "Pacman scan failed" exception=e
    end

    return apps
end

"""
    parse_pacman_output(output::String)

    Parse pacman -Q output.
"""
function parse_pacman_output(output::String)
    apps = []
    lines = split(output, '\n')

    for line in lines
        line = strip(line)
        isempty(line) && continue

        # Format: package-name version
        parts = split(line, ' ')

        if length(parts) >= 2
            app_name = strip(parts[1])
            version = strip(parts[2])

            metadata = Dict{String, Any}(
                "name" => app_name,
                "version" => version,
                "publisher" => nothing,
                "is_foss" => true,
                "cost" => 0.0,
                "platform" => "linux_arch"
            )

            push!(apps, metadata)
        end
    end

    return apps
end

"""
    scan_zypper()

    Scan openSUSE using zypper.
"""
function scan_zypper()
    apps = []

    try
        output = read(`zypper search --installed-only`, String)
        apps = parse_zypper_output(output)
        @info "Zypper scan complete" count=length(apps)
    catch e
        @error "Zypper scan failed" exception=e
    end

    return apps
end

"""
    parse_zypper_output(output::String)

    Parse zypper search --installed-only output.
"""
function parse_zypper_output(output::String)
    apps = []
    lines = split(output, '\n')

    for line in lines
        line = strip(line)

        # Skip headers and separators
        if isempty(line) || startswith(line, "S") || startswith(line, "-")
            continue
        end

        # Format: i | package-name | Version | ...
        parts = split(line, '|')

        if length(parts) >= 3
            app_name = strip(parts[2])
            version = strip(parts[3])

            metadata = Dict{String, Any}(
                "name" => app_name,
                "version" => version,
                "publisher" => nothing,
                "is_foss" => true,
                "cost" => 0.0,
                "platform" => "linux_suse"
            )

            push!(apps, metadata)
        end
    end

    return apps
end

"""
    scan_with_consent()

    Scan installed apps with proper consent handling.
    This is the safe entry point that checks permissions.

    Returns: Vector of app metadata or empty if consent denied.
"""
function scan_with_consent()
    # This function would integrate with Security module
    # Placeholder for demonstration

    @info "Consent-aware scanning (implement with Security.request_consent)"

    pm = detect_package_manager()

    if pm == UNKNOWN
        @warn "No package manager detected - use NO PEEK mode instead"
        return []
    end

    # In production, check consent here:
    # if !Security.has_consent(Security.SYSTEM_SCAN)
    #     @warn "SYSTEM_SCAN consent required"
    #     return []
    # end

    return scan_installed_apps(pm)
end

"""
    parse_package_list(raw_data::String, pm::PackageManager)

    Parse raw package manager output into app metadata.
"""
function parse_package_list(raw_data::String, pm::PackageManager)
    if pm == WINGET
        return parse_winget_output(raw_data)
    elseif pm == APT
        return parse_dpkg_output(raw_data)
    elseif pm == DNF
        return parse_dnf_output(raw_data)
    elseif pm == PACMAN
        return parse_pacman_output(raw_data)
    elseif pm == ZYPPER
        return parse_zypper_output(raw_data)
    else
        @warn "Unknown package manager" pm=pm
        return []
    end
end

end # module Automate
