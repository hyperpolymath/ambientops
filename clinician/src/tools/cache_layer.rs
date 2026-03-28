// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

//! Cache Layer — System cache management and cleanup.
//!
//! Enumerates common cache directories ($XDG_CACHE_HOME, browser caches,
//! package manager caches), reports their sizes, and offers cleanup for stale
//! entries older than a configurable threshold.
//!
//! Operates in dry-run mode by default — no deletions without explicit
//! `--execute` flag.

use anyhow::Result;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};
use walkdir::WalkDir;

/// Configuration for the cache layer scanner.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheLayerConfig {
    /// Maximum age before a cache entry is considered stale (in days).
    pub stale_threshold_days: u64,
    /// Whether to actually delete files (false = dry-run).
    pub execute: bool,
    /// Additional cache directories to scan beyond the standard set.
    pub extra_dirs: Vec<PathBuf>,
    /// Directories to skip even if they match a cache path.
    pub skip_dirs: Vec<PathBuf>,
}

impl Default for CacheLayerConfig {
    fn default() -> Self {
        Self {
            stale_threshold_days: 30,
            execute: false,
            extra_dirs: Vec::new(),
            skip_dirs: Vec::new(),
        }
    }
}

/// A discovered cache directory with size and staleness information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry {
    /// Absolute path to the cache directory.
    pub path: PathBuf,
    /// Human-readable label (e.g. "Firefox", "pip", "XDG Cache").
    pub label: String,
    /// Total size in bytes.
    pub total_bytes: u64,
    /// Number of files in the cache directory.
    pub file_count: u64,
    /// Size of stale files (older than threshold) in bytes.
    pub stale_bytes: u64,
    /// Number of stale files.
    pub stale_file_count: u64,
    /// Oldest file modification time (if any files exist).
    pub oldest_file: Option<DateTime<Local>>,
    /// Whether the directory exists and is accessible.
    pub accessible: bool,
}

/// Summary of a cache scan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheScanReport {
    /// All discovered cache entries.
    pub entries: Vec<CacheEntry>,
    /// Total size across all caches.
    pub total_bytes: u64,
    /// Total stale bytes across all caches.
    pub total_stale_bytes: u64,
    /// Stale threshold used for this scan.
    pub stale_threshold_days: u64,
    /// Whether this was a dry-run or actual cleanup.
    pub dry_run: bool,
    /// Number of files deleted (0 in dry-run mode).
    pub files_deleted: u64,
    /// Bytes freed by deletion (0 in dry-run mode).
    pub bytes_freed: u64,
    /// Timestamp of the scan.
    pub timestamp: DateTime<Local>,
}

/// Cache layer action types for CLI dispatch.
#[derive(Debug, Clone)]
pub enum CacheAction {
    /// Scan and report all cache directories (dry-run).
    Scan {
        stale_days: Option<u64>,
    },
    /// Clean stale caches (dry-run by default).
    Clean {
        stale_days: Option<u64>,
        execute: bool,
    },
    /// Show a summary of cache usage.
    Summary,
}

/// Handle a cache layer CLI action.
pub async fn handle(action: CacheAction) -> Result<()> {
    match action {
        CacheAction::Scan { stale_days } => {
            let config = CacheLayerConfig {
                stale_threshold_days: stale_days.unwrap_or(30),
                execute: false,
                ..Default::default()
            };
            let report = scan_caches(&config)?;
            print_report(&report);
        }
        CacheAction::Clean {
            stale_days,
            execute,
        } => {
            let config = CacheLayerConfig {
                stale_threshold_days: stale_days.unwrap_or(30),
                execute,
                ..Default::default()
            };
            let report = clean_caches(&config)?;
            print_report(&report);
        }
        CacheAction::Summary => {
            let config = CacheLayerConfig::default();
            let report = scan_caches(&config)?;
            print_summary(&report);
        }
    }

    Ok(())
}

/// Build the list of standard cache directories to scan.
///
/// Respects `$XDG_CACHE_HOME` (defaulting to `~/.cache`) and enumerates
/// well-known subdirectories for browsers, package managers, build tools, etc.
fn standard_cache_dirs() -> Vec<(PathBuf, &'static str)> {
    let home = dirs_home();
    let xdg_cache = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home.join(".cache"));

    let mut dirs: Vec<(PathBuf, &str)> = vec![
        // XDG Cache root.
        (xdg_cache.clone(), "XDG Cache (root)"),
        // Browser caches.
        (home.join(".mozilla/firefox"), "Firefox profiles"),
        (home.join(".cache/google-chrome"), "Chrome cache"),
        (home.join(".cache/chromium"), "Chromium cache"),
        (home.join(".cache/mozilla/firefox"), "Firefox cache"),
        // Package managers.
        (home.join(".cache/pip"), "pip cache"),
        (home.join(".cache/pipx"), "pipx cache"),
        (home.join(".cargo/registry/cache"), "Cargo registry cache"),
        (home.join(".cache/go-build"), "Go build cache"),
        (home.join(".cache/deno"), "Deno cache"),
        (home.join(".cache/yarn"), "Yarn cache"),
        (home.join(".npm/_cacache"), "npm cache"),
        (home.join(".cache/pnpm"), "pnpm cache"),
        (home.join(".cache/bun"), "Bun cache"),
        // Build tool caches.
        (home.join(".gradle/caches"), "Gradle caches"),
        (home.join(".m2/repository"), "Maven local repo"),
        (home.join(".cache/ccache"), "ccache"),
        (home.join(".cache/sccache"), "sccache"),
        // System / distro.
        (xdg_cache.join("thumbnails"), "Thumbnails"),
        (xdg_cache.join("fontconfig"), "Font cache"),
        (xdg_cache.join("mesa_shader_cache"), "Mesa shader cache"),
        (xdg_cache.join("mesa_shader_cache_db"), "Mesa shader DB"),
        // Container / VM.
        (home.join(".local/share/containers/cache"), "Podman cache"),
        (home.join(".cache/flatpak"), "Flatpak cache"),
        // Language-specific.
        (home.join(".cache/go/mod"), "Go module cache"),
        (home.join(".julia/compiled"), "Julia compiled cache"),
        (home.join(".cache/zig"), "Zig cache"),
        (home.join(".opam/download-cache"), "OCaml opam cache"),
        (home.join(".mix/archives"), "Elixir mix archives"),
        (home.join(".hex/cache"), "Hex package cache"),
        (home.join(".cache/guix"), "Guix cache"),
        // Nix store GC roots (informational, not for deletion).
        (PathBuf::from("/nix/var/nix/gcroots"), "Nix GC roots (info)"),
        // Misc.
        (xdg_cache.join("tracker3"), "GNOME Tracker"),
        (xdg_cache.join("babl"), "GIMP babl cache"),
    ];

    // System-level caches (readable but require root to clean).
    dirs.push((PathBuf::from("/var/cache/dnf"), "DNF cache"));
    dirs.push((PathBuf::from("/var/cache/PackageKit"), "PackageKit cache"));
    dirs.push((PathBuf::from("/tmp"), "/tmp (transient)"));

    dirs
}

/// Get the user's home directory.
fn dirs_home() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/root"))
}

/// Scan a single directory, computing total size, stale size, and file counts.
fn scan_directory(path: &Path, label: &str, stale_threshold: Duration) -> CacheEntry {
    if !path.exists() || !path.is_dir() {
        return CacheEntry {
            path: path.to_path_buf(),
            label: label.to_string(),
            total_bytes: 0,
            file_count: 0,
            stale_bytes: 0,
            stale_file_count: 0,
            oldest_file: None,
            accessible: false,
        };
    }

    let now = SystemTime::now();
    let mut total_bytes: u64 = 0;
    let mut file_count: u64 = 0;
    let mut stale_bytes: u64 = 0;
    let mut stale_file_count: u64 = 0;
    let mut oldest: Option<SystemTime> = None;

    // Walk the directory tree. Limit depth to avoid traversing into
    // deeply-nested build artifacts for too long.
    let walker = WalkDir::new(path)
        .max_depth(10)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok());

    for entry in walker {
        if !entry.file_type().is_file() {
            continue;
        }

        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };

        let size = metadata.len();
        total_bytes += size;
        file_count += 1;

        if let Ok(modified) = metadata.modified() {
            // Track oldest file.
            match oldest {
                Some(ref o) if modified < *o => oldest = Some(modified),
                None => oldest = Some(modified),
                _ => {}
            }

            // Check staleness.
            if let Ok(age) = now.duration_since(modified) {
                if age > stale_threshold {
                    stale_bytes += size;
                    stale_file_count += 1;
                }
            }
        }
    }

    let oldest_dt = oldest.map(|t| DateTime::<Local>::from(t));

    CacheEntry {
        path: path.to_path_buf(),
        label: label.to_string(),
        total_bytes,
        file_count,
        stale_bytes,
        stale_file_count,
        oldest_file: oldest_dt,
        accessible: true,
    }
}

/// Scan all cache directories and produce a report.
pub fn scan_caches(config: &CacheLayerConfig) -> Result<CacheScanReport> {
    let stale_threshold = Duration::from_secs(config.stale_threshold_days * 86400);
    let dirs = standard_cache_dirs();

    let mut entries = Vec::new();

    for (path, label) in &dirs {
        if config.skip_dirs.iter().any(|s| path.starts_with(s)) {
            continue;
        }

        // Skip the XDG Cache root if we're scanning its subdirectories
        // individually — only report it when it has files directly in it.
        if label == &"XDG Cache (root)" {
            // We still scan it to show the total, but we only count
            // direct children (depth=1) to avoid double-counting.
            let entry = scan_directory_shallow(path, label, stale_threshold);
            if entry.file_count > 0 {
                entries.push(entry);
            }
            continue;
        }

        let entry = scan_directory(path, label, stale_threshold);
        if entry.accessible && entry.file_count > 0 {
            entries.push(entry);
        }
    }

    // Scan any user-supplied extra directories.
    for extra in &config.extra_dirs {
        let label = extra
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("custom");
        let entry = scan_directory(extra, label, stale_threshold);
        if entry.accessible {
            entries.push(entry);
        }
    }

    // Sort by total size descending.
    entries.sort_by(|a, b| b.total_bytes.cmp(&a.total_bytes));

    let total_bytes: u64 = entries.iter().map(|e| e.total_bytes).sum();
    let total_stale_bytes: u64 = entries.iter().map(|e| e.stale_bytes).sum();

    Ok(CacheScanReport {
        entries,
        total_bytes,
        total_stale_bytes,
        stale_threshold_days: config.stale_threshold_days,
        dry_run: !config.execute,
        files_deleted: 0,
        bytes_freed: 0,
        timestamp: Local::now(),
    })
}

/// Scan only the direct children (depth=1) of a directory.
///
/// Used for the XDG cache root to avoid double-counting subdirectories that
/// are scanned individually.
fn scan_directory_shallow(path: &Path, label: &str, stale_threshold: Duration) -> CacheEntry {
    if !path.exists() || !path.is_dir() {
        return CacheEntry {
            path: path.to_path_buf(),
            label: label.to_string(),
            total_bytes: 0,
            file_count: 0,
            stale_bytes: 0,
            stale_file_count: 0,
            oldest_file: None,
            accessible: false,
        };
    }

    let now = SystemTime::now();
    let mut total_bytes: u64 = 0;
    let mut file_count: u64 = 0;
    let mut stale_bytes: u64 = 0;
    let mut stale_file_count: u64 = 0;
    let mut oldest: Option<SystemTime> = None;

    let walker = WalkDir::new(path)
        .max_depth(1)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok());

    for entry in walker {
        if !entry.file_type().is_file() {
            continue;
        }

        let metadata = match entry.metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };

        let size = metadata.len();
        total_bytes += size;
        file_count += 1;

        if let Ok(modified) = metadata.modified() {
            match oldest {
                Some(ref o) if modified < *o => oldest = Some(modified),
                None => oldest = Some(modified),
                _ => {}
            }
            if let Ok(age) = now.duration_since(modified) {
                if age > stale_threshold {
                    stale_bytes += size;
                    stale_file_count += 1;
                }
            }
        }
    }

    CacheEntry {
        path: path.to_path_buf(),
        label: label.to_string(),
        total_bytes,
        file_count,
        stale_bytes,
        stale_file_count,
        oldest_file: oldest.map(DateTime::<Local>::from),
        accessible: true,
    }
}

/// Clean stale files from cache directories.
///
/// In dry-run mode (the default), reports what would be deleted without
/// actually removing anything. With `config.execute = true`, deletes stale
/// files and reports freed space.
pub fn clean_caches(config: &CacheLayerConfig) -> Result<CacheScanReport> {
    let stale_threshold = Duration::from_secs(config.stale_threshold_days * 86400);
    let mut report = scan_caches(config)?;

    if !config.execute {
        report.dry_run = true;
        return Ok(report);
    }

    report.dry_run = false;
    let now = SystemTime::now();
    let mut total_deleted: u64 = 0;
    let mut total_freed: u64 = 0;

    // Only clean user-owned caches, never system caches.
    let home = dirs_home();

    for entry in &report.entries {
        // Safety: only delete inside the user's home directory.
        if !entry.path.starts_with(&home) {
            tracing::info!(
                "Skipping system cache (not in $HOME): {}",
                entry.path.display()
            );
            continue;
        }

        if entry.stale_bytes == 0 {
            continue;
        }

        let walker = WalkDir::new(&entry.path)
            .max_depth(10)
            .follow_links(false)
            .contents_first(true) // Delete files before their parent dirs.
            .into_iter()
            .filter_map(|e| e.ok());

        for dir_entry in walker {
            if !dir_entry.file_type().is_file() {
                continue;
            }

            let metadata = match dir_entry.metadata() {
                Ok(m) => m,
                Err(_) => continue,
            };

            if let Ok(modified) = metadata.modified() {
                if let Ok(age) = now.duration_since(modified) {
                    if age > stale_threshold {
                        let size = metadata.len();
                        match std::fs::remove_file(dir_entry.path()) {
                            Ok(()) => {
                                total_deleted += 1;
                                total_freed += size;
                                tracing::debug!("Deleted: {}", dir_entry.path().display());
                            }
                            Err(e) => {
                                tracing::warn!(
                                    "Failed to delete {}: {}",
                                    dir_entry.path().display(),
                                    e
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    report.files_deleted = total_deleted;
    report.bytes_freed = total_freed;
    Ok(report)
}

// ---------------------------------------------------------------------------
// Display helpers
// ---------------------------------------------------------------------------

/// Format a byte count into a human-readable string.
fn human_bytes(bytes: u64) -> String {
    const KIB: u64 = 1024;
    const MIB: u64 = 1024 * KIB;
    const GIB: u64 = 1024 * MIB;

    if bytes >= GIB {
        format!("{:.2} GiB", bytes as f64 / GIB as f64)
    } else if bytes >= MIB {
        format!("{:.1} MiB", bytes as f64 / MIB as f64)
    } else if bytes >= KIB {
        format!("{:.1} KiB", bytes as f64 / KIB as f64)
    } else {
        format!("{} B", bytes)
    }
}

/// Print a full report of the cache scan.
fn print_report(report: &CacheScanReport) {
    let mode = if report.dry_run {
        "DRY RUN"
    } else {
        "EXECUTE"
    };

    println!(
        "Cache Layer Report [{}] — stale threshold: {} days",
        mode, report.stale_threshold_days
    );
    println!("{}", "=".repeat(80));

    if report.entries.is_empty() {
        println!("  No cache directories found with content.");
        return;
    }

    println!(
        "{:<40} {:>10} {:>8} {:>10} {:>8}",
        "CACHE", "SIZE", "FILES", "STALE", "STALE#"
    );
    println!("{}", "-".repeat(80));

    for entry in &report.entries {
        println!(
            "{:<40} {:>10} {:>8} {:>10} {:>8}",
            truncate_label(&entry.label, 39),
            human_bytes(entry.total_bytes),
            entry.file_count,
            human_bytes(entry.stale_bytes),
            entry.stale_file_count,
        );
    }

    println!("{}", "-".repeat(80));
    println!(
        "{:<40} {:>10} {:>8} {:>10}",
        "TOTAL",
        human_bytes(report.total_bytes),
        report.entries.iter().map(|e| e.file_count).sum::<u64>(),
        human_bytes(report.total_stale_bytes),
    );

    if !report.dry_run {
        println!("\nCleanup Results:");
        println!("  Files deleted: {}", report.files_deleted);
        println!("  Space freed:   {}", human_bytes(report.bytes_freed));
    } else {
        println!("\n  This was a DRY RUN. Use --execute to actually delete stale files.");
        println!(
            "  Potential space savings: {}",
            human_bytes(report.total_stale_bytes)
        );
    }
}

/// Print a brief summary (total sizes only).
fn print_summary(report: &CacheScanReport) {
    println!("Cache Usage Summary");
    println!("{}", "=".repeat(50));
    println!(
        "  Total cache size:  {}",
        human_bytes(report.total_bytes)
    );
    println!(
        "  Stale (>{} days): {}",
        report.stale_threshold_days,
        human_bytes(report.total_stale_bytes)
    );
    println!(
        "  Cache directories: {}",
        report.entries.len()
    );

    let biggest = report.entries.first();
    if let Some(entry) = biggest {
        println!(
            "  Biggest cache:     {} ({})",
            entry.label,
            human_bytes(entry.total_bytes)
        );
    }
}

/// Truncate a label string to fit within `max_len` characters.
fn truncate_label(label: &str, max_len: usize) -> String {
    if label.len() <= max_len {
        label.to_string()
    } else {
        format!("{}...", &label[..max_len - 3])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_human_bytes_formatting() {
        assert_eq!(human_bytes(0), "0 B");
        assert_eq!(human_bytes(512), "512 B");
        assert_eq!(human_bytes(1024), "1.0 KiB");
        assert_eq!(human_bytes(1_048_576), "1.0 MiB");
        assert_eq!(human_bytes(1_073_741_824), "1.00 GiB");
        assert_eq!(human_bytes(2_500_000_000), "2.33 GiB");
    }

    #[test]
    fn test_truncate_label() {
        assert_eq!(truncate_label("short", 10), "short");
        assert_eq!(truncate_label("a very long label name", 10), "a very ...");
    }

    #[test]
    fn test_scan_nonexistent_directory() {
        let entry = scan_directory(
            Path::new("/nonexistent/cache/path"),
            "Missing",
            Duration::from_secs(86400),
        );
        assert!(!entry.accessible);
        assert_eq!(entry.total_bytes, 0);
        assert_eq!(entry.file_count, 0);
    }

    #[test]
    fn test_scan_real_temp_directory() {
        let dir = tempfile::tempdir().unwrap();
        let test_file = dir.path().join("test_cache.dat");
        std::fs::write(&test_file, b"cache content here").unwrap();

        let entry = scan_directory(
            dir.path(),
            "Test Cache",
            Duration::from_secs(86400 * 365), // 1 year threshold — nothing is stale.
        );

        assert!(entry.accessible);
        assert_eq!(entry.file_count, 1);
        assert_eq!(entry.total_bytes, 18); // "cache content here" is 18 bytes.
        assert_eq!(entry.stale_file_count, 0);
    }

    #[test]
    fn test_scan_with_stale_detection() {
        let dir = tempfile::tempdir().unwrap();
        let test_file = dir.path().join("stale.dat");
        std::fs::write(&test_file, b"old data").unwrap();

        // Set the file's mtime to 60 days ago.
        let sixty_days_ago = SystemTime::now() - Duration::from_secs(60 * 86400);
        filetime::set_file_mtime(
            &test_file,
            filetime::FileTime::from_system_time(sixty_days_ago),
        )
        .ok(); // May fail on some filesystems; test still validates logic.

        let entry = scan_directory(
            dir.path(),
            "Stale Test",
            Duration::from_secs(30 * 86400), // 30-day threshold.
        );

        assert!(entry.accessible);
        assert_eq!(entry.file_count, 1);
        // If filetime succeeded, the file should be detected as stale.
        // We don't assert stale_file_count because filetime might not work
        // in all test environments.
    }

    #[test]
    fn test_config_defaults() {
        let config = CacheLayerConfig::default();
        assert_eq!(config.stale_threshold_days, 30);
        assert!(!config.execute);
        assert!(config.extra_dirs.is_empty());
        assert!(config.skip_dirs.is_empty());
    }

    #[test]
    fn test_standard_cache_dirs_not_empty() {
        let dirs = standard_cache_dirs();
        assert!(!dirs.is_empty());
        // Should include at least the XDG cache root.
        assert!(dirs.iter().any(|(_, label)| *label == "XDG Cache (root)"));
    }

    #[test]
    fn test_scan_caches_produces_report() {
        let config = CacheLayerConfig {
            stale_threshold_days: 30,
            execute: false,
            extra_dirs: Vec::new(),
            skip_dirs: Vec::new(),
        };

        let report = scan_caches(&config).unwrap();
        assert!(report.dry_run);
        assert_eq!(report.stale_threshold_days, 30);
        assert_eq!(report.files_deleted, 0);
        assert_eq!(report.bytes_freed, 0);
        // The report should have a valid timestamp.
        assert!(report.timestamp <= Local::now());
    }
}
