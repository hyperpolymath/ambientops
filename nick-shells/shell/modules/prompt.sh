# SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <hyperpolymath>
#
# Prompt Module
# =============
# Simple, informative prompt with exit code display.

# Format: [exit_code] user@host:dir $
__ns_prompt() {
    local exit_code=$?
    local prompt_char='$'
    [ "$(id -u)" -eq 0 ] && prompt_char='#'

    if [ $exit_code -ne 0 ]; then
        printf '\001\033[31m\002[%d]\001\033[0m\002 ' "$exit_code"
    fi
    printf '\001\033[32m\002%s\001\033[0m\002@\001\033[34m\002%s\001\033[0m\002:\001\033[36m\002%s\001\033[0m\002 %s ' \
        "${USER:-$(whoami)}" \
        "${HOSTNAME%%.*}" \
        "${PWD/#$HOME/\~}" \
        "$prompt_char"
}

# Only set prompt for interactive shells
case $- in
    *i*)
        if [ -n "${BASH_VERSION:-}" ]; then
            PROMPT_COMMAND='PS1="$(__ns_prompt)"'
        elif [ -n "${ZSH_VERSION:-}" ]; then
            precmd() { PS1="$(__ns_prompt)" }
        else
            PS1='$ '
        fi
        ;;
esac

# vim: ft=sh ts=4 sw=4 et
