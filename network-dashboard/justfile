# SPDX-License-Identifier: PMPL-1.0-or-later
# Justfile - Network dashboard deployment automation

default:
    @just --list

# Deploy network dashboard to Kubernetes cluster
deploy:
    @echo "Deploying network dashboard..."
    kubectl apply -f manifests/namespace.yaml
    kubectl apply -f manifests/configmap.yaml
    kubectl apply -f manifests/deployment.yaml
    kubectl apply -f manifests/service.yaml
    @echo "Network dashboard deployed"
    @just status

# Remove network dashboard from cluster
undeploy:
    @echo "Removing network dashboard..."
    kubectl delete -f manifests/ --ignore-not-found=true
    @echo "Cleanup complete"

# Show deployment status
status:
    @echo "=== Network Dashboard Status ==="
    @kubectl -n flatracoon-dashboard get all 2>/dev/null || echo "Not deployed yet"

# Start local development server
dev:
    mix phx.server

# Run setup (fetch deps)
setup:
    mix deps.get

# Build release
build:
    MIX_ENV=prod mix release

# Watch pod logs
logs:
    kubectl -n flatracoon-dashboard logs -f deployment/network-dashboard

# Validate manifests
validate:
    @echo "Validating Kubernetes manifests..."
    @for file in manifests/*.yaml; do \
        echo "Checking $$file..."; \
        kubectl apply --dry-run=client -f $$file > /dev/null; \
    done
    @echo "All manifests valid"

# Run lint checks
lint:
    mix format --check-formatted

# Run tests
test:
    mix test

# Clean build artifacts
clean:
    mix clean

# Format code
fmt:
    mix format

# Run all checks
check: lint test

# Prepare a release
release VERSION:
    @echo "Releasing {{VERSION}}..."
