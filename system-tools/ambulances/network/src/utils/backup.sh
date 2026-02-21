#!/usr/bin/env bash
# Backup utilities for configuration files

# Backup directory
BACKUP_DIR="${BACKUP_DIR:-${HOME}/.network-repair-backups}"

# Initialize backup system
init_backup() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        mkdir -p "${BACKUP_DIR}" || {
            log_error "Failed to create backup directory: ${BACKUP_DIR}"
            return 1
        }
    fi
    log_debug "Backup directory: ${BACKUP_DIR}"
}

# Create backup of a file
backup_file() {
    local file="$1"
    local backup_name="$2"

    if [[ ! -f "${file}" ]]; then
        log_debug "File does not exist, skipping backup: ${file}"
        return 0
    fi

    init_backup || return 1

    # Generate backup filename
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    if [[ -n "${backup_name}" ]]; then
        local backup_file="${BACKUP_DIR}/${backup_name}.${timestamp}"
    else
        # Use sanitized version of original path
        local sanitized
        sanitized="$(echo "${file}" | tr '/' '_' | sed 's/^_//')"
        local backup_file="${BACKUP_DIR}/${sanitized}.${timestamp}"
    fi

    # Create backup
    if run_privileged cp -p "${file}" "${backup_file}"; then
        log_success "Backed up: ${file} → ${backup_file}"
        echo "${backup_file}"
        return 0
    else
        log_error "Failed to backup: ${file}"
        return 1
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    local target_file="$2"

    if [[ ! -f "${backup_file}" ]]; then
        log_error "Backup file not found: ${backup_file}"
        return 1
    fi

    if run_privileged cp -p "${backup_file}" "${target_file}"; then
        log_success "Restored: ${backup_file} → ${target_file}"
        return 0
    else
        log_error "Failed to restore: ${backup_file}"
        return 1
    fi
}

# List backups
list_backups() {
    if [[ ! -d "${BACKUP_DIR}" ]]; then
        log_info "No backups found"
        return 0
    fi

    log_info "Backups in ${BACKUP_DIR}:"
    ls -lh "${BACKUP_DIR}" 2>/dev/null || log_info "No backups found"
}

# Clean old backups (keep last N)
clean_old_backups() {
    local keep="${1:-10}"

    if [[ ! -d "${BACKUP_DIR}" ]]; then
        return 0
    fi

    log_info "Cleaning old backups (keeping last ${keep})..."

    local count
    count=$(find "${BACKUP_DIR}" -type f | wc -l)

    if [[ ${count} -gt ${keep} ]]; then
        find "${BACKUP_DIR}" -type f -printf '%T+ %p\n' | \
            sort -r | \
            tail -n +$((keep + 1)) | \
            cut -d' ' -f2- | \
            while IFS= read -r file; do
                rm -f "${file}"
                log_debug "Removed old backup: ${file}"
            done
    fi
}
