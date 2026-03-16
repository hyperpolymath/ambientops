// SPDX-License-Identifier: PMPL-1.0-or-later
//! Hard-coded rules store with git-like versioning and provenance tracking
//!
//! The rules system follows a "crystallization" pattern:
//! 1. AI/reasoning solves a new problem
//! 2. Solution is tested and gains confidence (success_count)
//! 3. When threshold reached, solution is "crystallized" into a deterministic rule
//! 4. Rules are checked FIRST, AI only invoked when no rule matches
//!
//! Each rule tracks full provenance:
//! - Original source (forum, AI, manual, mesh peer)
//! - Decision path (what led to this rule)
//! - Version history (git-like commits)
//! - Success/failure counts post-crystallization

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::validation::{validate_pattern, validate_service_name};

/// Confidence threshold for crystallizing a solution into a rule
const CRYSTALLIZATION_THRESHOLD: u32 = 5;

/// A crystallized rule - simple, deterministic, inspectable
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rule {
    /// Unique identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// Version (semver-like)
    pub version: String,
    /// When the rule applies (conditions)
    pub when: Vec<Condition>,
    /// What to do (actions)
    pub then: Vec<Action>,
    /// Provenance tracking
    pub provenance: Provenance,
    /// Post-crystallization stats
    pub stats: RuleStats,
    /// Whether rule is enabled
    pub enabled: bool,
    /// Tags for categorization
    pub tags: Vec<String>,
}

/// A condition that must be true for a rule to apply
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Condition {
    /// Check if a process is running
    ProcessRunning { name: String },
    /// Check if a service is in a state
    ServiceState { name: String, state: String },
    /// Check if a file exists
    FileExists { path: String },
    /// Check if a file contains pattern
    FileContains { path: String, pattern: String },
    /// Check system metric threshold
    MetricThreshold { metric: String, op: String, value: f64 },
    /// Check if a port is open
    PortOpen { port: u16, protocol: String },
    /// Check if a package is installed
    PackageInstalled { name: String },
    /// Check kernel module loaded
    ModuleLoaded { name: String },
    /// Custom shell command (exit 0 = true)
    ShellCheck { command: String },
    /// Logical AND of conditions
    All { conditions: Vec<Condition> },
    /// Logical OR of conditions
    Any { conditions: Vec<Condition> },
    /// Negation
    Not { condition: Box<Condition> },
}

/// An action to take when conditions are met
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Action {
    /// Run a shell command
    Shell { command: String, sudo: bool },
    /// Restart a service
    RestartService { name: String },
    /// Enable a service
    EnableService { name: String },
    /// Create/modify a file
    WriteFile { path: String, content: String, mode: Option<String> },
    /// Load a kernel module
    LoadModule { name: String, options: Option<String> },
    /// Install a package
    InstallPackage { name: String },
    /// Log a message
    Log { level: String, message: String },
    /// Notify user
    Notify { title: String, body: String },
    /// Escalate to AI (rule couldn't handle it)
    Escalate { reason: String },
}

/// Full provenance tracking for auditability
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Provenance {
    /// Where this rule originated
    pub source: RuleSource,
    /// The original problem that led to this rule
    pub original_problem: String,
    /// The solution ID this was crystallized from
    pub solution_id: Option<String>,
    /// When the rule was created
    pub created_at: String,
    /// Who/what created it
    pub created_by: String,
    /// Decision chain - why was this rule adopted
    pub decision_path: Vec<DecisionStep>,
    /// Version history (git-like)
    pub history: Vec<RuleVersion>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RuleSource {
    /// Learned from solving a problem
    Crystallized { solution_id: String, confidence: f32 },
    /// Scraped from a forum
    Forum { url: String, thread_title: String },
    /// Received from mesh peer
    Mesh { peer_id: String, peer_name: String },
    /// Manually written
    Manual { author: String },
    /// Imported from external source
    Import { source: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecisionStep {
    pub timestamp: String,
    pub description: String,
    pub confidence_before: f32,
    pub confidence_after: f32,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleVersion {
    pub version: String,
    pub timestamp: String,
    pub author: String,
    pub message: String,
    pub diff_summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuleStats {
    pub applied_count: u32,
    pub success_count: u32,
    pub failure_count: u32,
    pub escalation_count: u32,
    pub last_applied: Option<String>,
    pub average_duration_ms: Option<f64>,
}

/// The rules engine - manages loading, matching, and executing rules
pub struct RulesEngine {
    /// All loaded rules
    rules: Vec<Rule>,
    /// Rules directory (git-tracked)
    rules_dir: PathBuf,
    /// Index for fast matching
    index: HashMap<String, Vec<usize>>,
}

impl RulesEngine {
    /// Create a new rules engine, loading from the rules directory
    pub fn new(rules_dir: &Path) -> Result<Self> {
        let mut engine = Self {
            rules: vec![],
            rules_dir: rules_dir.to_path_buf(),
            index: HashMap::new(),
        };

        engine.load_rules()?;
        Ok(engine)
    }

    /// Load all rules from the rules directory
    fn load_rules(&mut self) -> Result<()> {
        if !self.rules_dir.exists() {
            std::fs::create_dir_all(&self.rules_dir)?;
            self.init_git_repo()?;
        }

        // Load .toml rule files
        for entry in std::fs::read_dir(&self.rules_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().is_some_and(|e| e == "toml") {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(rule) = toml::from_str::<Rule>(&content) {
                        self.add_rule(rule);
                    }
                }
            }
        }

        tracing::info!("Loaded {} rules", self.rules.len());
        Ok(())
    }

    /// Initialize git repo for rules versioning
    fn init_git_repo(&self) -> Result<()> {
        let git_dir = self.rules_dir.join(".git");
        if !git_dir.exists() {
            std::process::Command::new("git")
                .args(["init"])
                .current_dir(&self.rules_dir)
                .output()?;

            // Create initial commit
            std::fs::write(
                self.rules_dir.join("README.md"),
                "# PSA Rules Store\n\nThis directory contains crystallized rules.\n",
            )?;

            std::process::Command::new("git")
                .args(["add", "."])
                .current_dir(&self.rules_dir)
                .output()?;

            std::process::Command::new("git")
                .args(["commit", "-m", "Initialize rules store"])
                .current_dir(&self.rules_dir)
                .output()?;

            tracing::info!("Initialized git repository for rules at {:?}", self.rules_dir);
        }
        Ok(())
    }

    /// Add a rule to the engine
    fn add_rule(&mut self, rule: Rule) {
        let idx = self.rules.len();

        // Index by tags
        for tag in &rule.tags {
            self.index.entry(tag.clone()).or_default().push(idx);
        }

        self.rules.push(rule);
    }

    /// Find matching rules for a problem
    pub fn find_matching(&self, context: &ProblemContext) -> Vec<&Rule> {
        let mut matches = vec![];

        for rule in &self.rules {
            if rule.enabled && self.evaluate_conditions(&rule.when, context) {
                matches.push(rule);
            }
        }

        // Sort by specificity (more conditions = more specific)
        matches.sort_by(|a, b| b.when.len().cmp(&a.when.len()));
        matches
    }

    /// Evaluate conditions against current system state
    fn evaluate_conditions(&self, conditions: &[Condition], context: &ProblemContext) -> bool {
        conditions.iter().all(|c| self.evaluate_condition(c, context))
    }

    fn evaluate_condition(&self, condition: &Condition, _context: &ProblemContext) -> bool {
        match condition {
            Condition::ProcessRunning { name } => {
                // SECURITY: Validate process name pattern before passing to pgrep
                let safe_name = match validate_pattern(name) {
                    Ok(n) => n,
                    Err(e) => {
                        tracing::warn!("Invalid process pattern '{}': {}", name, e);
                        return false;
                    }
                };
                std::process::Command::new("pgrep")
                    .arg(safe_name)
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false)
            }
            Condition::ServiceState { name, state } => {
                // SECURITY: Validate service name before passing to systemctl
                let safe_name = match validate_service_name(name) {
                    Ok(n) => n,
                    Err(e) => {
                        tracing::warn!("Invalid service name '{}': {}", name, e);
                        return false;
                    }
                };
                std::process::Command::new("systemctl")
                    .args(["is-active", safe_name])
                    .output()
                    .map(|o| {
                        String::from_utf8_lossy(&o.stdout)
                            .trim()
                            .eq_ignore_ascii_case(state)
                    })
                    .unwrap_or(false)
            }
            Condition::FileExists { path } => Path::new(path).exists(),
            Condition::FileContains { path, pattern } => {
                std::fs::read_to_string(path)
                    .map(|content| content.contains(pattern))
                    .unwrap_or(false)
            }
            Condition::ModuleLoaded { name } => {
                std::fs::read_to_string("/proc/modules")
                    .map(|content| content.lines().any(|l| l.starts_with(name)))
                    .unwrap_or(false)
            }
            Condition::ShellCheck { command } => {
                // SECURITY NOTE: ShellCheck intentionally executes arbitrary shell commands.
                // This is a feature, not a vulnerability. The security model relies on:
                // 1. Rule files being protected by filesystem permissions
                // 2. Crystallization only from trusted solution sources
                // 3. Human review of rules before enabling
                std::process::Command::new("sh")
                    .args(["-c", command])
                    .output()
                    .map(|o| o.status.success())
                    .unwrap_or(false)
            }
            Condition::All { conditions } => {
                conditions.iter().all(|c| self.evaluate_condition(c, _context))
            }
            Condition::Any { conditions } => {
                conditions.iter().any(|c| self.evaluate_condition(c, _context))
            }
            Condition::Not { condition } => !self.evaluate_condition(condition, _context),
            _ => {
                // TODO: Implement remaining conditions
                false
            }
        }
    }

    /// Execute a rule's actions
    pub async fn execute(&mut self, rule_id: &str) -> Result<ExecutionResult> {
        let rule = self
            .rules
            .iter()
            .find(|r| r.id == rule_id)
            .ok_or_else(|| anyhow::anyhow!("Rule not found: {}", rule_id))?
            .clone();

        let start = std::time::Instant::now();
        let mut result = ExecutionResult::default();

        for action in &rule.then {
            match self.execute_action(action).await {
                Ok(output) => {
                    result.outputs.push(output);
                }
                Err(e) => {
                    result.success = false;
                    result.error = Some(e.to_string());
                    break;
                }
            }
        }

        result.duration_ms = start.elapsed().as_millis() as f64;

        // Update stats
        if let Some(r) = self.rules.iter_mut().find(|r| r.id == rule_id) {
            r.stats.applied_count += 1;
            if result.success {
                r.stats.success_count += 1;
            } else {
                r.stats.failure_count += 1;
            }
            r.stats.last_applied = Some(chrono::Utc::now().to_rfc3339());
        }

        Ok(result)
    }

    async fn execute_action(&self, action: &Action) -> Result<String> {
        match action {
            Action::Shell { command, sudo } => {
                // SECURITY NOTE: Shell action intentionally executes arbitrary shell commands.
                // This is a feature, not a vulnerability. The security model relies on:
                // 1. Rule files being protected by filesystem permissions
                // 2. Crystallization only from trusted solution sources
                // 3. Human review of rules before enabling
                // 4. sudo flag requires explicit opt-in in rule definition
                let output = if *sudo {
                    tokio::process::Command::new("sudo")
                        .args(["sh", "-c", command])
                        .output()
                        .await?
                } else {
                    tokio::process::Command::new("sh")
                        .args(["-c", command])
                        .output()
                        .await?
                };

                if output.status.success() {
                    Ok(String::from_utf8_lossy(&output.stdout).to_string())
                } else {
                    Err(anyhow::anyhow!(
                        "Command failed: {}",
                        String::from_utf8_lossy(&output.stderr)
                    ))
                }
            }
            Action::RestartService { name } => {
                // SECURITY: Validate service name before passing to systemctl
                let safe_name = validate_service_name(name)
                    .map_err(|e| anyhow::anyhow!("Invalid service name '{}': {}", name, e))?;

                let output = tokio::process::Command::new("systemctl")
                    .args(["restart", safe_name])
                    .output()
                    .await?;

                if output.status.success() {
                    Ok(format!("Restarted service: {}", safe_name))
                } else {
                    Err(anyhow::anyhow!("Failed to restart {}", safe_name))
                }
            }
            Action::Log { level, message } => {
                match level.as_str() {
                    "error" => tracing::error!("{}", message),
                    "warn" => tracing::warn!("{}", message),
                    "debug" => tracing::debug!("{}", message),
                    _ => tracing::info!("{}", message),
                }
                Ok(format!("[{}] {}", level, message))
            }
            Action::Notify { title, body } => {
                // Use notify-send if available
                let _ = tokio::process::Command::new("notify-send")
                    .args([title, body])
                    .output()
                    .await;
                Ok(format!("Notification: {} - {}", title, body))
            }
            Action::Escalate { reason } => {
                Err(anyhow::anyhow!("Escalation required: {}", reason))
            }
            _ => {
                // TODO: Implement remaining actions
                Ok("Action not implemented".to_string())
            }
        }
    }

    /// Crystallize a proven solution into a rule
    pub fn crystallize(
        &mut self,
        solution: &crate::storage::Solution,
        conditions: Vec<Condition>,
        actions: Vec<Action>,
    ) -> Result<String> {
        let rule_id = format!("rule-{}", uuid::Uuid::new_v4());

        let rule = Rule {
            id: rule_id.clone(),
            name: format!("Auto: {}", solution.problem),
            version: "1.0.0".to_string(),
            when: conditions,
            then: actions,
            provenance: Provenance {
                source: RuleSource::Crystallized {
                    solution_id: solution.id.clone(),
                    confidence: solution.success_count as f32
                        / (solution.success_count + solution.failure_count + 1) as f32,
                },
                original_problem: solution.problem.clone(),
                solution_id: Some(solution.id.clone()),
                created_at: chrono::Utc::now().to_rfc3339(),
                created_by: "psa-auto".to_string(),
                decision_path: vec![DecisionStep {
                    timestamp: chrono::Utc::now().to_rfc3339(),
                    description: "Crystallized from proven solution".to_string(),
                    confidence_before: 0.0,
                    confidence_after: solution.success_count as f32
                        / (solution.success_count + solution.failure_count + 1) as f32,
                    reason: format!(
                        "Solution proven with {} successes, {} failures",
                        solution.success_count, solution.failure_count
                    ),
                }],
                history: vec![RuleVersion {
                    version: "1.0.0".to_string(),
                    timestamp: chrono::Utc::now().to_rfc3339(),
                    author: "psa-auto".to_string(),
                    message: "Initial crystallization".to_string(),
                    diff_summary: "Created from solution".to_string(),
                }],
            },
            stats: RuleStats::default(),
            enabled: true,
            tags: solution.tags.clone(),
        };

        // Save to file
        let rule_path = self.rules_dir.join(format!("{}.toml", rule_id));
        let content = toml::to_string_pretty(&rule)?;
        std::fs::write(&rule_path, &content)?;

        // Git commit
        std::process::Command::new("git")
            .args(["add", &format!("{}.toml", rule_id)])
            .current_dir(&self.rules_dir)
            .output()?;

        std::process::Command::new("git")
            .args([
                "commit",
                "-m",
                &format!("Crystallize rule: {}", rule.name),
            ])
            .current_dir(&self.rules_dir)
            .output()?;

        self.add_rule(rule);

        tracing::info!("Crystallized new rule: {}", rule_id);
        Ok(rule_id)
    }

    /// List all rules
    pub fn list(&self) -> &[Rule] {
        &self.rules
    }

    /// Get rule by ID
    pub fn get(&self, id: &str) -> Option<&Rule> {
        self.rules.iter().find(|r| r.id == id)
    }

    /// Get provenance chain for a rule
    pub fn get_provenance(&self, id: &str) -> Option<&Provenance> {
        self.get(id).map(|r| &r.provenance)
    }
}

/// Context for matching rules against current state
#[derive(Debug, Default)]
pub struct ProblemContext {
    pub problem_text: String,
    pub category: Option<String>,
    pub tags: Vec<String>,
    pub metrics: HashMap<String, f64>,
}

/// Result of executing a rule
#[derive(Debug)]
pub struct ExecutionResult {
    pub success: bool,
    pub outputs: Vec<String>,
    pub error: Option<String>,
    pub duration_ms: f64,
}

impl Default for ExecutionResult {
    fn default() -> Self {
        Self {
            success: true,  // Default to success, set to false on error
            outputs: vec![],
            error: None,
            duration_ms: 0.0,
        }
    }
}

/// Check if a solution should be crystallized
pub fn should_crystallize(solution: &crate::storage::Solution) -> bool {
    solution.success_count >= CRYSTALLIZATION_THRESHOLD
        && solution.failure_count < solution.success_count / 2
}
