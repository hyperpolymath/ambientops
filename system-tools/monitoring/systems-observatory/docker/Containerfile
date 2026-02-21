FROM julia:1.8

# Set working directory
WORKDIR /app

# Copy project files
COPY Project.toml ./
COPY src/ ./src/
COPY data/ ./data/
COPY test/ ./test/

# Install dependencies
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Run privacy self-audit during build (fails build if privacy violated)
RUN julia --project=. -e 'include("src/security.jl"); using .Security; checks = Security.self_audit(); all_passed = all(c -> c.passed, checks); if !all_passed exit(1) end; println("✓ Privacy audit passed during Docker build")'

# Set entrypoint to CLI
ENTRYPOINT ["julia", "--project=.", "-e", "include(\"src/cli.jl\"); using .CLI; CLI.run()"]

# Metadata
LABEL maintainer="Juisys Project"
LABEL description="Privacy-first GDPR-compliant application auditing tool"
LABEL privacy="100% local processing, no network calls, ephemeral data only"
LABEL version="1.0.0"
