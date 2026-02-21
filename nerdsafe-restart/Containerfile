# SPDX-License-Identifier: AGPL-3.0-or-later
# nerdsafe-restart container image
# Build: nerdctl build -t nerdsafe-restart .
# Run:   nerdctl run --rm -v $HOME:$HOME:ro nerdsafe-restart check

FROM registry.fedoraproject.org/fedora:43

LABEL org.opencontainers.image.title="nerdsafe-restart"
LABEL org.opencontainers.image.description="Pre-reboot validation for paranoid sysadmins"
LABEL org.opencontainers.image.source="https://github.com/hyperpolymath/nerdsafe-restart"
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"

# Install validation tools
RUN dnf install -y --setopt=install_weak_deps=False \
    bash \
    coreutils \
    findutils \
    gawk \
    grep \
    procps-ng \
    ShellCheck \
    util-linux \
    && dnf clean all

# Copy validation scripts
COPY nerdsafe-restart.sh /usr/local/bin/nerdsafe-restart
RUN chmod +x /usr/local/bin/nerdsafe-restart

# Default to running validation
ENTRYPOINT ["/usr/local/bin/nerdsafe-restart"]
CMD ["check"]
