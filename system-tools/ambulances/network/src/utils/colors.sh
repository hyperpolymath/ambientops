#!/usr/bin/env bash
# Color definitions for terminal output

# Check if we should use colors
USE_COLORS="${USE_COLORS:-auto}"

# Determine if terminal supports colors
supports_colors() {
    if [[ "${USE_COLORS}" == "never" ]]; then
        return 1
    elif [[ "${USE_COLORS}" == "always" ]]; then
        return 0
    else
        # Auto-detect
        [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]
    fi
}

# Initialize colors
if supports_colors; then
    # Regular colors
    COLOR_BLACK="$(tput setaf 0 2>/dev/null || echo '')"
    COLOR_RED="$(tput setaf 1 2>/dev/null || echo '')"
    COLOR_GREEN="$(tput setaf 2 2>/dev/null || echo '')"
    COLOR_YELLOW="$(tput setaf 3 2>/dev/null || echo '')"
    COLOR_BLUE="$(tput setaf 4 2>/dev/null || echo '')"
    COLOR_MAGENTA="$(tput setaf 5 2>/dev/null || echo '')"
    COLOR_CYAN="$(tput setaf 6 2>/dev/null || echo '')"
    COLOR_WHITE="$(tput setaf 7 2>/dev/null || echo '')"

    # Text attributes
    COLOR_BOLD="$(tput bold 2>/dev/null || echo '')"
    COLOR_DIM="$(tput dim 2>/dev/null || echo '')"
    COLOR_UNDERLINE="$(tput smul 2>/dev/null || echo '')"
    COLOR_RESET="$(tput sgr0 2>/dev/null || echo '')"
else
    # No colors
    COLOR_BLACK=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_WHITE=""
    COLOR_BOLD=""
    COLOR_DIM=""
    COLOR_UNDERLINE=""
    COLOR_RESET=""
fi

# Export colors
export COLOR_BLACK COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE
export COLOR_MAGENTA COLOR_CYAN COLOR_WHITE COLOR_BOLD COLOR_DIM
export COLOR_UNDERLINE COLOR_RESET
