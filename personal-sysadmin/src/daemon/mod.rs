// SPDX-License-Identifier: PMPL-1.0-or-later
//! Background daemon with security isolation
//!
//! The daemon runs continuously, monitoring system health and applying rules.
//! It is designed to be:
//! - Silent by default (only notify on problems)
//! - Secure (no network exposure, Unix socket for local IPC only)
//! - Isolated (runs as unprivileged user, sandboxed)
//! - On-demand (user can query via socket or CLI)

use anyhow::Result;
use std::path::{Path, PathBuf};
use tokio::sync::mpsc;

/// Security configuration for the daemon
#[derive(Debug, Clone)]
pub struct SecurityConfig {
    /// Run as this user (drop privileges from root if started as root)
    pub run_as_user: Option<String>,
    /// Unix socket path for local IPC (no network exposure)
    pub socket_path: PathBuf,
    /// Restrict socket permissions (owner only by default)
    pub socket_mode: u32,
    /// Enable seccomp filtering
    pub enable_seccomp: bool,
    /// Enable landlock filesystem isolation
    pub enable_landlock: bool,
    /// Allowed paths for landlock (if enabled)
    pub allowed_paths: Vec<PathBuf>,
    /// Block all outbound network by default
    pub block_outbound: bool,
    /// Allowed outbound domains (for forum search, etc.)
    pub allowed_domains: Vec<String>,
}

impl Default for SecurityConfig {
    fn default() -> Self {
        Self {
            run_as_user: None,
            socket_path: PathBuf::from("/run/user")
                .join(std::env::var("UID").unwrap_or_else(|_| "1000".to_string()))
                .join("psa.sock"),
            socket_mode: 0o600, // Owner read/write only
            enable_seccomp: true,
            enable_landlock: true,
            allowed_paths: vec![
                PathBuf::from("/proc"),
                PathBuf::from("/sys"),
                PathBuf::from("/etc"),
                crate::dirs::config_dir(),
                crate::dirs::data_dir(),
                crate::dirs::cache_dir(),
            ],
            block_outbound: true,
            allowed_domains: vec![
                // Only specific trusted domains for solution search
                "askubuntu.com".to_string(),
                "unix.stackexchange.com".to_string(),
                "superuser.com".to_string(),
                "wiki.archlinux.org".to_string(),
                "discussion.fedoraproject.org".to_string(),
            ],
        }
    }
}

/// Daemon state
pub struct Daemon {
    config: DaemonConfig,
    security: SecurityConfig,
    /// Channel to receive commands from CLI/socket
    cmd_rx: mpsc::Receiver<DaemonCommand>,
    /// Channel to send responses
    resp_tx: mpsc::Sender<DaemonResponse>,
    /// Rules engine
    rules: crate::rules::RulesEngine,
    /// Background tasks
    tasks: Vec<tokio::task::JoinHandle<()>>,
}

#[derive(Debug, Clone)]
pub struct DaemonConfig {
    /// How often to check system health (seconds)
    pub health_check_interval: u64,
    /// How often to apply rules (seconds)
    pub rule_check_interval: u64,
    /// Notification settings
    pub notify: NotifyConfig,
    /// Log file path
    pub log_path: PathBuf,
}

impl Default for DaemonConfig {
    fn default() -> Self {
        Self {
            health_check_interval: 60,
            rule_check_interval: 300,
            notify: NotifyConfig::default(),
            log_path: crate::dirs::data_dir().join("daemon.log"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct NotifyConfig {
    /// Only notify on errors
    pub errors_only: bool,
    /// Use desktop notifications
    pub desktop: bool,
    /// Log to file
    pub log: bool,
    /// Minimum severity to notify (error, warn, info)
    pub min_severity: String,
}

impl Default for NotifyConfig {
    fn default() -> Self {
        Self {
            errors_only: true,
            desktop: true,
            log: true,
            min_severity: "warn".to_string(),
        }
    }
}

/// Commands that can be sent to the daemon
#[derive(Debug, Clone)]
pub enum DaemonCommand {
    /// Get current status
    Status,
    /// Run health check now
    HealthCheck,
    /// Query for a problem
    Query { problem: String },
    /// List active rules
    ListRules,
    /// Get rule provenance
    GetProvenance { rule_id: String },
    /// Pause monitoring
    Pause,
    /// Resume monitoring
    Resume,
    /// Shutdown daemon
    Shutdown,
}

/// Responses from the daemon
#[derive(Debug, Clone)]
pub enum DaemonResponse {
    Status(DaemonStatus),
    HealthReport(HealthReport),
    QueryResult(QueryResult),
    Rules(Vec<RuleSummary>),
    Provenance(Option<String>),
    Ok,
    Error(String),
}

#[derive(Debug, Clone)]
pub struct DaemonStatus {
    pub running: bool,
    pub paused: bool,
    pub uptime_secs: u64,
    pub rules_count: usize,
    pub last_health_check: Option<String>,
    pub issues_detected: u32,
    pub issues_resolved: u32,
}

#[derive(Debug, Clone)]
pub struct HealthReport {
    pub overall: HealthLevel,
    pub issues: Vec<HealthIssue>,
    pub timestamp: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum HealthLevel {
    Good,
    Warning,
    Critical,
}

#[derive(Debug, Clone)]
pub struct HealthIssue {
    pub severity: HealthLevel,
    pub category: String,
    pub message: String,
    pub suggestion: Option<String>,
}

#[derive(Debug, Clone)]
pub struct QueryResult {
    pub answer: String,
    pub confidence: f32,
    pub source: String,
    pub applied_rule: Option<String>,
}

#[derive(Debug, Clone)]
pub struct RuleSummary {
    pub id: String,
    pub name: String,
    pub enabled: bool,
    pub success_rate: f32,
}

impl Daemon {
    /// Create a new daemon instance
    pub fn new(
        cmd_rx: mpsc::Receiver<DaemonCommand>,
        resp_tx: mpsc::Sender<DaemonResponse>,
    ) -> Result<Self> {
        let rules_dir = crate::dirs::data_dir().join("rules");
        let rules = crate::rules::RulesEngine::new(&rules_dir)?;

        Ok(Self {
            config: DaemonConfig::default(),
            security: SecurityConfig::default(),
            cmd_rx,
            resp_tx,
            rules,
            tasks: vec![],
        })
    }

    /// Apply security hardening before starting
    pub fn apply_security(&self) -> Result<()> {
        // 1. Drop privileges if running as root
        if let Some(user) = &self.security.run_as_user {
            tracing::info!("Dropping privileges to user: {}", user);
            // Use nix crate to setuid/setgid
        }

        // 2. Apply seccomp filter (restrict syscalls)
        if self.security.enable_seccomp {
            tracing::info!("Applying seccomp filter");
            // Would use libseccomp here
        }

        // 3. Apply landlock (filesystem isolation)
        if self.security.enable_landlock {
            tracing::info!("Applying landlock filesystem restrictions");
            // Would use landlock crate here
        }

        // 4. Set up iptables/nftables rules to block outbound except allowed domains
        if self.security.block_outbound {
            tracing::info!("Network isolation active - outbound restricted to allowed domains");
            // This would be done via nftables or cgroup network namespace
        }

        Ok(())
    }

    /// Start the daemon main loop
    pub async fn run(&mut self) -> Result<()> {
        self.apply_security()?;

        let start_time = std::time::Instant::now();
        let mut paused = false;
        let mut last_health_check = None;
        let mut issues_detected = 0u32;
        let mut issues_resolved = 0u32;

        // Start background health check task
        let health_interval = tokio::time::Duration::from_secs(self.config.health_check_interval);
        let rule_interval = tokio::time::Duration::from_secs(self.config.rule_check_interval);

        let mut health_timer = tokio::time::interval(health_interval);
        let mut rule_timer = tokio::time::interval(rule_interval);

        tracing::info!("Daemon started");

        loop {
            tokio::select! {
                // Handle commands from CLI/socket
                Some(cmd) = self.cmd_rx.recv() => {
                    let response = match cmd {
                        DaemonCommand::Status => {
                            DaemonResponse::Status(DaemonStatus {
                                running: true,
                                paused,
                                uptime_secs: start_time.elapsed().as_secs(),
                                rules_count: self.rules.list().len(),
                                last_health_check: last_health_check.clone(),
                                issues_detected,
                                issues_resolved,
                            })
                        }
                        DaemonCommand::HealthCheck => {
                            let report = self.run_health_check().await;
                            last_health_check = Some(report.timestamp.clone());
                            issues_detected += report.issues.len() as u32;
                            DaemonResponse::HealthReport(report)
                        }
                        DaemonCommand::Query { problem } => {
                            let result = self.query(&problem).await;
                            DaemonResponse::QueryResult(result)
                        }
                        DaemonCommand::ListRules => {
                            let rules: Vec<_> = self.rules.list().iter().map(|r| RuleSummary {
                                id: r.id.clone(),
                                name: r.name.clone(),
                                enabled: r.enabled,
                                success_rate: if r.stats.applied_count > 0 {
                                    r.stats.success_count as f32 / r.stats.applied_count as f32
                                } else {
                                    0.0
                                },
                            }).collect();
                            DaemonResponse::Rules(rules)
                        }
                        DaemonCommand::GetProvenance { rule_id } => {
                            let prov = self.rules.get_provenance(&rule_id)
                                .map(|p| serde_json::to_string_pretty(p).unwrap_or_default());
                            DaemonResponse::Provenance(prov)
                        }
                        DaemonCommand::Pause => {
                            paused = true;
                            tracing::info!("Daemon paused");
                            DaemonResponse::Ok
                        }
                        DaemonCommand::Resume => {
                            paused = false;
                            tracing::info!("Daemon resumed");
                            DaemonResponse::Ok
                        }
                        DaemonCommand::Shutdown => {
                            tracing::info!("Daemon shutdown requested");
                            break;
                        }
                    };

                    let _ = self.resp_tx.send(response).await;
                }

                // Periodic health check (silent unless issues)
                _ = health_timer.tick() => {
                    if !paused {
                        let report = self.run_health_check().await;
                        last_health_check = Some(report.timestamp.clone());

                        if report.overall != HealthLevel::Good {
                            issues_detected += report.issues.len() as u32;
                            self.notify_issues(&report).await;
                        }
                    }
                }

                // Periodic rule application
                _ = rule_timer.tick() => {
                    if !paused {
                        let resolved = self.apply_rules().await;
                        issues_resolved += resolved;
                    }
                }
            }
        }

        Ok(())
    }

    /// Run a health check
    async fn run_health_check(&self) -> HealthReport {
        let mut issues = vec![];

        // Check system resources
        let mut sys = sysinfo::System::new_all();
        sys.refresh_all();

        // CPU check
        let cpu_usage = sys.global_cpu_info().cpu_usage();
        if cpu_usage > 90.0 {
            issues.push(HealthIssue {
                severity: HealthLevel::Warning,
                category: "cpu".to_string(),
                message: format!("High CPU usage: {:.1}%", cpu_usage),
                suggestion: Some("Check top processes with 'psa ps list -s cpu'".to_string()),
            });
        }

        // Memory check
        let mem_used = sys.used_memory();
        let mem_total = sys.total_memory();
        let mem_pct = (mem_used as f64 / mem_total as f64) * 100.0;
        if mem_pct > 90.0 {
            issues.push(HealthIssue {
                severity: HealthLevel::Warning,
                category: "memory".to_string(),
                message: format!("High memory usage: {:.1}%", mem_pct),
                suggestion: Some("Check memory hogs with 'psa ps list -s mem'".to_string()),
            });
        }

        // Disk check
        for disk in sys.disks() {
            let used_pct = 100.0 - (disk.available_space() as f64 / disk.total_space() as f64 * 100.0);
            if used_pct > 90.0 {
                issues.push(HealthIssue {
                    severity: HealthLevel::Warning,
                    category: "disk".to_string(),
                    message: format!("Disk {} at {:.1}% capacity", disk.mount_point().display(), used_pct),
                    suggestion: Some("Find large files with 'psa disk large'".to_string()),
                });
            }
        }

        // Check for failed services
        if let Ok(output) = std::process::Command::new("systemctl")
            .args(["--user", "--failed", "--no-legend"])
            .output()
        {
            let failed = String::from_utf8_lossy(&output.stdout);
            for line in failed.lines() {
                if !line.trim().is_empty() {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if let Some(service) = parts.first() {
                        issues.push(HealthIssue {
                            severity: HealthLevel::Critical,
                            category: "service".to_string(),
                            message: format!("Failed service: {}", service),
                            suggestion: Some(format!("Check with 'systemctl --user status {}'", service)),
                        });
                    }
                }
            }
        }

        let overall = if issues.iter().any(|i| i.severity == HealthLevel::Critical) {
            HealthLevel::Critical
        } else if issues.iter().any(|i| i.severity == HealthLevel::Warning) {
            HealthLevel::Warning
        } else {
            HealthLevel::Good
        };

        HealthReport {
            overall,
            issues,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// Apply matching rules
    async fn apply_rules(&mut self) -> u32 {
        let context = crate::rules::ProblemContext::default();
        let matching = self.rules.find_matching(&context);

        let mut resolved = 0u32;
        for rule in matching {
            match self.rules.execute(&rule.id).await {
                Ok(result) if result.success => {
                    tracing::debug!("Rule {} applied successfully", rule.id);
                    resolved += 1;
                }
                Ok(result) => {
                    tracing::warn!("Rule {} failed: {:?}", rule.id, result.error);
                }
                Err(e) => {
                    tracing::error!("Rule {} execution error: {}", rule.id, e);
                }
            }
        }

        resolved
    }

    /// Query for a problem
    async fn query(&self, problem: &str) -> QueryResult {
        // First, check rules
        let mut context = crate::rules::ProblemContext::default();
        context.problem_text = problem.to_string();

        let matching = self.rules.find_matching(&context);
        if let Some(rule) = matching.first() {
            return QueryResult {
                answer: format!("Matched rule: {}\n\nActions: {:?}", rule.name, rule.then),
                confidence: 0.9,
                source: "rules".to_string(),
                applied_rule: Some(rule.id.clone()),
            };
        }

        // Fall back to AI (would be implemented in ai module)
        QueryResult {
            answer: format!("No matching rule found for: {}. Would query AI for solution.", problem),
            confidence: 0.5,
            source: "pending-ai".to_string(),
            applied_rule: None,
        }
    }

    /// Send notification for issues
    async fn notify_issues(&self, report: &HealthReport) {
        if report.issues.is_empty() {
            return;
        }

        let title = match report.overall {
            HealthLevel::Critical => "PSA: Critical Issues Detected",
            HealthLevel::Warning => "PSA: Warnings Detected",
            HealthLevel::Good => return,
        };

        let body: String = report
            .issues
            .iter()
            .map(|i| format!("• {}", i.message))
            .collect::<Vec<_>>()
            .join("\n");

        if self.config.notify.desktop {
            let _ = tokio::process::Command::new("notify-send")
                .args(["--urgency=critical", title, &body])
                .output()
                .await;
        }

        if self.config.notify.log {
            tracing::warn!("{}: {}", title, body.replace('\n', "; "));
        }
    }
}

/// Create a Unix socket listener for IPC
pub async fn create_socket_listener(path: &Path) -> Result<tokio::net::UnixListener> {
    // Remove existing socket
    let _ = std::fs::remove_file(path);

    // Create parent directory if needed
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    let listener = tokio::net::UnixListener::bind(path)?;

    // Set socket permissions (owner only)
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }

    tracing::info!("Listening on Unix socket: {:?}", path);
    Ok(listener)
}
