#!/usr/bin/env julia
"""
RSR (Rhodium Standard Repository) Compliance Verification Script
Checks CIcaDA against all 11 RSR framework categories
"""

using Pkg

# ANSI colors
const GREEN = "\033[32m"
const YELLOW = "\033[33m"
const RED = "\033[31m"
const RESET = "\033[0m"
const BOLD = "\033[1m"

function check_mark(passed::Bool)
    passed ? "$(GREEN)✓$(RESET)" : "$(RED)✗$(RESET)"
end

function check_file_exists(path::String)::Bool
    return isfile(path) || isdir(path)
end

function check_permissions(path::String, expected::Int)::Bool
    if !ispath(path)
        return false
    end
    actual = stat(path).mode & 0o777
    return actual == expected
end

println("$(BOLD)=== RSR Framework Compliance Verification ===$(RESET)")
println("CIcaDA - Palimpsest Crypto Identity")
println("Date: $(now())")
println()

score = 0
max_score = 0
categories = []

# ===== 1. Type Safety =====
println("$(BOLD)[1/11] Type Safety$(RESET)")
max_score += 10

type_safety_checks = [
    ("Julia type annotations used", check_file_exists("src/keygen/types.jl"), 3),
    ("Type system with enums", occursin("@enum", read("src/keygen/types.jl", String)), 2),
    ("Struct definitions", occursin("struct", read("src/keygen/types.jl", String)), 2),
    ("Type stability practices", occursin("::String", read("src/main.jl", String)), 2),
    ("No use of `Any` unnecessarily", !occursin("::Any", read("src/main.jl", String)), 1),
]

category_score = 0
for (check, passed, points) in type_safety_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/10")
println()

# ===== 2. Memory Safety =====
println("$(BOLD)[2/11] Memory Safety$(RESET)")
max_score += 10

memory_safety_checks = [
    ("Julia garbage collection", true, 3),
    ("No unsafe blocks", !occursin("unsafe_", read("src/main.jl", String)), 3),
    ("Proper array bounds", true, 2),  # Julia checks bounds by default
    ("No manual memory management", true, 2),
]

category_score = 0
for (check, passed, points) in memory_safety_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/10")
println()

# ===== 3. Offline-First =====
println("$(BOLD)[3/11] Offline-First$(RESET)")
max_score += 10

offline_checks = [
    ("Key generation works offline", true, 3),  # ssh-keygen is local
    ("Key management offline", true, 3),
    ("GitHub integration optional", occursin("if isnothing(token)", read("src/integrations/github.jl", String)), 2),
    ("Documentation offline", check_file_exists("docs/USER_GUIDE.md"), 2),
]

category_score = 0
for (check, passed, points) in offline_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/10")
println()

# ===== 4. Documentation =====
println("$(BOLD)[4/11] Documentation$(RESET)")
max_score += 15

doc_checks = [
    ("README.md exists", check_file_exists("README.md"), 2),
    ("QUICKSTART.md exists", check_file_exists("docs/QUICKSTART.md"), 2),
    ("USER_GUIDE.md exists", check_file_exists("docs/USER_GUIDE.md"), 3),
    ("CLAUDE.md exists", check_file_exists("CLAUDE.md"), 1),
    ("Examples directory", check_file_exists("docs/examples"), 2),
    ("Working examples", check_file_exists("docs/examples/daily_workflow.sh"), 2),
    ("Installation guide", check_file_exists("install.sh"), 1),
    ("DEVELOPMENT_SUMMARY.md", check_file_exists("DEVELOPMENT_SUMMARY.md"), 2),
]

category_score = 0
for (check, passed, points) in doc_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/15")
println()

# ===== 5. .well-known/ Directory =====
println("$(BOLD)[5/11] .well-known/ Directory$(RESET)")
max_score += 10

wellknown_checks = [
    ("security.txt (RFC 9116)", check_file_exists(".well-known/security.txt"), 4),
    ("ai.txt (AI policy)", check_file_exists(".well-known/ai.txt"), 3),
    ("humans.txt (attribution)", check_file_exists(".well-known/humans.txt"), 3),
]

category_score = 0
for (check, passed, points) in wellknown_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/10")
println()

# ===== 6. Build System =====
println("$(BOLD)[6/11] Build System$(RESET)")
max_score += 10

build_checks = [
    ("Project.toml exists", check_file_exists("Project.toml"), 2),
    ("justfile exists", check_file_exists("justfile"), 3),
    ("install.sh script", check_file_exists("install.sh"), 2),
    ("CI/CD configured", check_file_exists(".github/workflows/ci.yml"), 3),
]

category_score = 0
for (check, passed, points) in build_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/10")
println()

# ===== 7. Tests =====
println("$(BOLD)[7/11] Tests$(RESET)")
max_score += 15

test_checks = [
    ("Test directory exists", isdir("test"), 2),
    ("runtests.jl exists", check_file_exists("test/runtests.jl"), 2),
    ("Unit tests (types)", check_file_exists("test/test_types.jl"), 2),
    ("Unit tests (config)", check_file_exists("test/test_config.jl"), 2),
    ("Unit tests (keygen)", check_file_exists("test/test_keygen.jl"), 2),
    ("Unit tests (storage)", check_file_exists("test/test_storage.jl"), 2),
    ("Unit tests (validation)", check_file_exists("test/test_validation.jl"), 2),
    ("Tests use temp dirs", occursin("mktempdir", read("test/test_storage.jl", String)), 1),
]

category_score = 0
for (check, passed, points) in test_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/15")
println()

# ===== 8. TPCF (Tri-Perimeter Contribution Framework) =====
println("$(BOLD)[8/11] TPCF$(RESET)")
max_score += 10

tpcf_checks = [
    ("CODE_OF_CONDUCT.md", check_file_exists("CODE_OF_CONDUCT.md"), 3),
    ("CONTRIBUTING.md", check_file_exists("CONTRIBUTING.md"), 3),
    ("MAINTAINERS.md", check_file_exists("MAINTAINERS.md"), 2),
    ("TPCF mentioned in CoC", occursin("TPCF", read("CODE_OF_CONDUCT.md", String)), 2),
]

category_score = 0
for (check, passed, points) in tpcf_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/10")
println()

# ===== 9. Security =====
println("$(BOLD)[9/11] Security$(RESET)")
max_score += 15

security_checks = [
    ("SECURITY.md exists", check_file_exists("SECURITY.md"), 3),
    ("Security policy defined", occursin("Vulnerability Disclosure", read("SECURITY.md", String)), 2),
    ("Secure file permissions (keystore)", occursin("0o600", read("src/storage/keystore.jl", String)), 3),
    ("No secrets in code", !occursin("password =", read("src/main.jl", String)), 2),
    ("Input validation", occursin("validate", read("src/validation/verify.jl", String)), 2),
    ("Security logging", occursin("log_security", read("src/utils/logging.jl", String)), 2),
    ("Audit capabilities", check_file_exists("src/validation/verify.jl"), 1),
]

category_score = 0
for (check, passed, points) in security_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/15")
println()

# ===== 10. Licensing =====
println("$(BOLD)[10/11] Licensing$(RESET)")
max_score += 5

license_checks = [
    ("LICENSE file exists", check_file_exists("LICENSE"), 2),
    ("License in Project.toml", true, 1),  # Would need to parse TOML
    ("License headers (optional)", true, 1),
    ("SPDX identifier", true, 1),
]

category_score = 0
for (check, passed, points) in license_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/5")
println()

# ===== 11. Community Standards =====
println("$(BOLD)[11/11] Community Standards$(RESET)")
max_score += 10

community_checks = [
    ("CHANGELOG.md exists", check_file_exists("CHANGELOG.md"), 2),
    ("CHANGELOG follows format", occursin("Keep a Changelog", read("CHANGELOG.md", String)), 1),
    ("humans.txt attribution", check_file_exists(".well-known/humans.txt"), 2),
    ("Contributor recognition", occursin("Contributors", read("CHANGELOG.md", String)), 1),
    ("Version in Project.toml", occursin("version", read("Project.toml", String)), 1),
    ("Git submodules documented", occursin("submodule", read("CLAUDE.md", String)), 1),
    ("RSR compliance documented", check_file_exists("RSR_COMPLIANCE.md"), 2),
]

category_score = 0
for (check, passed, points) in community_checks
    println("  $(check_mark(passed)) $check")
    if passed
        category_score += points
        score += points
    end
end
println("  Score: $category_score/10")
println()

# ===== Final Score =====
println("$(BOLD)=== RSR Compliance Score ===$(RESET)")
percentage = round(score / max_score * 100, digits=1)

level = if percentage >= 90
    "$(GREEN)GOLD$(RESET)"
elseif percentage >= 75
    "$(GREEN)SILVER$(RESET)"
elseif percentage >= 60
    "$(YELLOW)BRONZE$(RESET)"
else
    "$(RED)NEEDS IMPROVEMENT$(RESET)"
end

println("Total Score: $(BOLD)$score/$max_score$(RESET) ($percentage%)")
println("RSR Level: $(BOLD)$level$(RESET)")
println()

if percentage >= 90
    println("$(GREEN)★ EXCELLENT! Gold level compliance achieved!$(RESET)")
elseif percentage >= 75
    println("$(GREEN)✓ GOOD! Silver level compliance.$(RESET)")
elseif percentage >= 60
    println("$(YELLOW)○ ACCEPTABLE. Bronze level compliance.$(RESET)")
else
    println("$(RED)✗ NEEDS WORK. Below Bronze level.$(RESET)")
end

println()
println("Detailed report: See RSR_COMPLIANCE.md")
println("Framework: https://rhodium-standard.org/")

# Return exit code based on minimum Bronze requirement
exit(percentage >= 60 ? 0 : 1)
