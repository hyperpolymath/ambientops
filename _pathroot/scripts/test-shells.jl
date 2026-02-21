#!/usr/bin/env julia
# SPDX-License-Identifier: PMPL-1.0-or-later
# Test suite for 22-shell compatibility matrix

using Test

# Shell definitions
const SHELLS = [
    ("bash", "bash/pathroot.sh", ["/bin/bash", "/usr/bin/bash"]),
    ("zsh", "zsh/pathroot.zsh", ["/bin/zsh", "/usr/bin/zsh"]),
    ("fish", "fish/pathroot.fish", ["/usr/bin/fish"]),
    ("dash", "dash/pathroot.sh", ["/bin/dash", "/usr/bin/dash"]),
    ("ksh", "ksh/pathroot.ksh", ["/bin/ksh", "/usr/bin/ksh"]),
    ("mksh", "mksh/pathroot.sh", ["/bin/mksh", "/usr/bin/mksh"]),
    ("yash", "yash/pathroot.sh", ["/usr/bin/yash"]),
    ("tcsh", "tcsh/pathroot.csh", ["/bin/tcsh", "/usr/bin/tcsh"]),
    ("csh", "csh/pathroot.csh", ["/bin/csh", "/usr/bin/csh"]),
    ("ash", "ash/pathroot.sh", ["/bin/ash"]),
    ("nushell", "nushell/pathroot.nu", ["/usr/bin/nu"]),
    ("elvish", "elvish/pathroot.elv", ["/usr/bin/elvish"]),
    ("ion", "ion/pathroot.sh", ["/usr/bin/ion"]),
    ("oil", "oil/pathroot.oil", ["/usr/bin/oil", "/usr/bin/osh"]),
    ("xonsh", "xonsh/pathroot.xsh", ["/usr/bin/xonsh"]),
    ("powershell", "powershell/pathroot.ps1", ["/usr/bin/pwsh"]),
    ("pwsh", "pwsh/pathroot.ps1", ["/usr/bin/pwsh"]),
    ("cmd", "cmd/pathroot.cmd", ["cmd.exe"]),
    ("rc", "rc/pathroot.sh", ["/usr/bin/rc"]),
    ("es", "es/pathroot.sh", ["/usr/bin/es"]),
    ("scsh", "scsh/pathroot.sh", ["/usr/bin/scsh"]),
    ("minix-sh", "minix-sh/pathroot.sh", ["/bin/sh"]),
]

"""
    check_shell_available(shell_paths)

Check if any of the shell paths exist on the system
"""
function check_shell_available(shell_paths::Vector{String})
    for path in shell_paths
        if isfile(path)
            return (true, path)
        end
    end
    return (false, nothing)
end

"""
    test_shell_script(name, script_path, shell_binary)

Test if a shell script exists and is executable
"""
function test_shell_script(name::String, script_path::String, shell_binary::Union{String,Nothing})
    base_dir = dirname(@__DIR__)
    full_path = joinpath(base_dir, "scripts", "all-shells", script_path)

    # Test 1: Script exists
    if !isfile(full_path)
        @warn "Script missing: $full_path"
        return false
    end

    # Test 2: Script is executable (on Unix)
    if Sys.isunix()
        mode = filemode(full_path)
        is_executable = (mode & 0o111) != 0
        if !is_executable
            @warn "Script not executable: $full_path"
            return false
        end
    end

    # Test 3: If shell is available, try to parse script
    if !isnothing(shell_binary)
        # Just check syntax without running
        # Different shells have different syntax checkers
        if occursin(r"(bash|dash|ksh|ash|mksh|yash)", name)
            try
                run(pipeline(`$shell_binary -n $full_path`, stdout=devnull, stderr=devnull))
            catch e
                @warn "Script syntax error for $name: $e"
                return false
            end
        end
    end

    return true
end

"""
    test_detect_shell_script()

Test the shell detection router
"""
function test_detect_shell_script()
    base_dir = dirname(@__DIR__)
    detect_script = joinpath(base_dir, "scripts", "detect-shell.sh")

    @test isfile(detect_script)

    if Sys.isunix()
        mode = filemode(detect_script)
        @test (mode & 0o111) != 0
    end
end

# Run tests
@testset "22-Shell Compatibility Matrix" begin
    println("\n=== Testing Shell Compatibility ===\n")

    available_count = 0
    tested_count = 0
    passed_count = 0

    for (name, script_path, shell_paths) in SHELLS
        (available, shell_binary) = check_shell_available(shell_paths)

        status_emoji = available ? "✓" : "○"
        status_text = available ? "available" : "not installed"

        println("$status_emoji $name ($status_text)")

        if available
            available_count += 1
            tested_count += 1

            if test_shell_script(name, script_path, shell_binary)
                passed_count += 1
            end
        else
            # Still test that script exists
            if test_shell_script(name, script_path, nothing)
                passed_count += 1
            end
            tested_count += 1
        end
    end

    println("\n=== Summary ===")
    println("Total shells: $(length(SHELLS))")
    println("Scripts created: $passed_count/$(length(SHELLS))")
    println("Shells available on system: $available_count/$(length(SHELLS))")

    @testset "Shell Scripts Exist" begin
        for (name, script_path, _) in SHELLS
            base_dir = dirname(@__DIR__)
            full_path = joinpath(base_dir, "scripts", "all-shells", script_path)
            @test isfile(full_path) "Missing script: $name"
        end
    end

    @testset "Shell Detection Router" begin
        test_detect_shell_script()
    end
end

println("\n✅ Shell compatibility matrix tests complete!")
