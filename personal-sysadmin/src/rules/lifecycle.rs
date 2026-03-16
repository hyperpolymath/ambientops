// SPDX-License-Identifier: PMPL-1.0-or-later
//! Rule lifecycle management - monitoring, tolerance, and obsolescence detection
//!
//! This module handles:
//! - Success/failure tracking with statistical tolerance
//! - Rule versioning (don't overwrite for minor variations)
//! - Obsolescence detection (CVE fixed, package updated, etc.)
//! - New rule proposal workflow
//! - Rule retirement and archival

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Tolerance configuration for rule updates
#[derive(Debug, Clone)]
pub struct ToleranceConfig {
    /// Minimum success rate before considering modification
    pub min_success_rate: f32,
    /// Minimum applications before statistical significance
    pub min_samples: u32,
    /// Variance threshold - don't update if difference is within this %
    pub variance_threshold: f32,
    /// How many failures before flagging for review
    pub failure_review_threshold: u32,
    /// Time window for rate calculations (seconds)
    pub rate_window_secs: u64,
}

impl Default for ToleranceConfig {
    fn default() -> Self {
        Self {
            min_success_rate: 0.8,    // 80% success required
            min_samples: 10,           // At least 10 applications
            variance_threshold: 0.05,  // 5% variance tolerance
            failure_review_threshold: 3, // Review after 3 failures
            rate_window_secs: 604800,  // 1 week window
        }
    }
}

/// Rule health status
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum RuleHealth {
    /// Rule is working well
    Healthy,
    /// Rule is degrading (success rate dropping)
    Degrading { current_rate: f32, trend: f32 },
    /// Rule needs review (failures above threshold)
    NeedsReview { reason: String },
    /// Rule may be obsolete (no longer applicable)
    PossiblyObsolete { reason: String },
    /// Rule confirmed obsolete and should be retired
    Obsolete { reason: String, retired_at: String },
    /// Rule is new and being evaluated
    Probationary { applications: u32, required: u32 },
}

/// Reasons a rule might become obsolete
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ObsolescenceReason {
    /// CVE was fixed upstream
    CveFixed { cve_id: String, fixed_version: String },
    /// Package was updated
    PackageUpdated { package: String, old_version: String, new_version: String },
    /// Condition no longer applies (file removed, service gone, etc.)
    ConditionInvalid { condition: String },
    /// Superseded by another rule
    Superseded { new_rule_id: String },
    /// Manually deprecated
    ManualDeprecation { reason: String, by: String },
    /// No applications in time window
    NoRecentActivity { last_applied: String },
}

/// A proposed new rule (not yet crystallized)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleProposal {
    pub id: String,
    pub problem_pattern: String,
    pub suggested_conditions: Vec<super::Condition>,
    pub suggested_actions: Vec<super::Action>,
    pub evidence: Vec<ProposalEvidence>,
    pub confidence: f32,
    pub status: ProposalStatus,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProposalEvidence {
    pub timestamp: String,
    pub source: String,
    pub outcome: EvidenceOutcome,
    pub context: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EvidenceOutcome {
    Success,
    Failure { error: String },
    Partial { details: String },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ProposalStatus {
    /// Collecting evidence
    Gathering { count: u32, required: u32 },
    /// Ready for review
    PendingReview,
    /// Approved for crystallization
    Approved { by: String },
    /// Rejected
    Rejected { reason: String },
    /// Crystallized into a rule
    Crystallized { rule_id: String },
}

/// Rule lifecycle manager
pub struct LifecycleManager {
    tolerance: ToleranceConfig,
    /// Active proposals
    proposals: HashMap<String, RuleProposal>,
    /// Rule health cache
    health_cache: HashMap<String, RuleHealth>,
    /// CVE tracking (would integrate with NIST NVD or similar)
    known_cves: HashMap<String, CveStatus>,
}

#[derive(Debug, Clone)]
pub struct CveStatus {
    pub id: String,
    pub affected_packages: Vec<String>,
    pub fixed_in: Option<String>,
    pub patched_locally: bool,
    pub related_rule_ids: Vec<String>,
}

impl LifecycleManager {
    pub fn new(tolerance: ToleranceConfig) -> Self {
        Self {
            tolerance,
            proposals: HashMap::new(),
            health_cache: HashMap::new(),
            known_cves: HashMap::new(),
        }
    }

    /// Assess the health of a rule based on its statistics
    pub fn assess_health(&mut self, rule: &super::Rule) -> RuleHealth {
        let stats = &rule.stats;

        // New rule in probationary period
        if stats.applied_count < self.tolerance.min_samples {
            return RuleHealth::Probationary {
                applications: stats.applied_count,
                required: self.tolerance.min_samples,
            };
        }

        // Calculate success rate
        let success_rate = stats.success_count as f32 / stats.applied_count as f32;

        // Check for recent failures
        if stats.failure_count >= self.tolerance.failure_review_threshold
            && stats.failure_count as f32 / stats.applied_count as f32 > 0.3
        {
            return RuleHealth::NeedsReview {
                reason: format!(
                    "High failure rate: {} failures out of {} applications",
                    stats.failure_count, stats.applied_count
                ),
            };
        }

        // Check for escalations (rule couldn't handle, had to ask AI)
        if stats.escalation_count > stats.success_count / 2 {
            return RuleHealth::NeedsReview {
                reason: format!(
                    "High escalation rate: {} escalations",
                    stats.escalation_count
                ),
            };
        }

        // Check for no recent activity (possibly obsolete)
        if let Some(last) = &stats.last_applied {
            if let Ok(last_time) = chrono::DateTime::parse_from_rfc3339(last) {
                let age = chrono::Utc::now().signed_duration_since(last_time.with_timezone(&chrono::Utc));
                if age.num_seconds() > self.tolerance.rate_window_secs as i64 * 4 {
                    return RuleHealth::PossiblyObsolete {
                        reason: format!("No applications in {} days", age.num_days()),
                    };
                }
            }
        }

        // Check for degrading performance (would need historical data)
        if success_rate < self.tolerance.min_success_rate {
            return RuleHealth::Degrading {
                current_rate: success_rate,
                trend: -0.1, // Would calculate from history
            };
        }

        // Cache and return
        let health = RuleHealth::Healthy;
        self.health_cache.insert(rule.id.clone(), health.clone());
        health
    }

    /// Check if a proposed change is within tolerance (don't update for minor variations)
    pub fn within_tolerance(
        &self,
        existing: &super::Rule,
        proposed_conditions: &[super::Condition],
        proposed_actions: &[super::Action],
    ) -> bool {
        // Count differences in conditions
        let condition_diff = self.count_condition_differences(&existing.when, proposed_conditions);
        let action_diff = self.count_action_differences(&existing.then, proposed_actions);

        // If differences are minor (e.g., just parameter tweaks), consider within tolerance
        let total_elements = existing.when.len() + existing.then.len();
        let total_diff = condition_diff + action_diff;

        if total_elements == 0 {
            return total_diff == 0;
        }

        let diff_ratio = total_diff as f32 / total_elements as f32;
        diff_ratio <= self.tolerance.variance_threshold
    }

    fn count_condition_differences(&self, a: &[super::Condition], b: &[super::Condition]) -> usize {
        // Simple count - real implementation would do semantic comparison
        if a.len() != b.len() {
            return a.len().abs_diff(b.len());
        }
        // Would compare each condition semantically
        0
    }

    fn count_action_differences(&self, a: &[super::Action], b: &[super::Action]) -> usize {
        if a.len() != b.len() {
            return a.len().abs_diff(b.len());
        }
        0
    }

    /// Propose a new rule based on observed solutions
    pub fn propose_rule(
        &mut self,
        problem_pattern: &str,
        conditions: Vec<super::Condition>,
        actions: Vec<super::Action>,
        initial_evidence: ProposalEvidence,
    ) -> String {
        let id = format!("proposal-{}", uuid::Uuid::new_v4());

        let proposal = RuleProposal {
            id: id.clone(),
            problem_pattern: problem_pattern.to_string(),
            suggested_conditions: conditions,
            suggested_actions: actions,
            evidence: vec![initial_evidence],
            confidence: 0.1,
            status: ProposalStatus::Gathering { count: 1, required: 5 },
            created_at: chrono::Utc::now().to_rfc3339(),
        };

        tracing::info!("New rule proposal created: {} for '{}'", id, problem_pattern);
        self.proposals.insert(id.clone(), proposal);
        id
    }

    /// Add evidence to a proposal
    pub fn add_evidence(&mut self, proposal_id: &str, evidence: ProposalEvidence) -> Result<()> {
        let proposal = self
            .proposals
            .get_mut(proposal_id)
            .ok_or_else(|| anyhow::anyhow!("Proposal not found: {}", proposal_id))?;

        proposal.evidence.push(evidence.clone());

        // Recalculate confidence
        let successes = proposal
            .evidence
            .iter()
            .filter(|e| matches!(e.outcome, EvidenceOutcome::Success))
            .count();
        proposal.confidence = successes as f32 / proposal.evidence.len() as f32;

        // Check if ready for review
        if let ProposalStatus::Gathering { count, required } = &proposal.status {
            let new_count = *count + 1;
            if new_count >= *required {
                proposal.status = ProposalStatus::PendingReview;
                tracing::info!(
                    "Proposal {} ready for review (confidence: {:.1}%)",
                    proposal_id,
                    proposal.confidence * 100.0
                );
            } else {
                proposal.status = ProposalStatus::Gathering {
                    count: new_count,
                    required: *required,
                };
            }
        }

        Ok(())
    }

    /// Check if a rule has become obsolete due to CVE fix
    pub fn check_cve_obsolescence(&self, rule: &super::Rule) -> Option<ObsolescenceReason> {
        // Check if rule was created for a CVE
        if let super::RuleSource::Forum { url, .. } = &rule.provenance.source {
            // Check for CVE pattern in URL or problem
            for (cve_id, status) in &self.known_cves {
                if rule.provenance.original_problem.contains(cve_id) {
                    if let Some(fixed_in) = &status.fixed_in {
                        // Check if current package version >= fixed version
                        // Would use package manager to check
                        return Some(ObsolescenceReason::CveFixed {
                            cve_id: cve_id.clone(),
                            fixed_version: fixed_in.clone(),
                        });
                    }
                }
            }
        }
        None
    }

    /// Check if rule conditions are still valid
    pub async fn check_condition_validity(&self, rule: &super::Rule) -> Option<ObsolescenceReason> {
        for condition in &rule.when {
            match condition {
                super::Condition::FileExists { path } => {
                    // If rule expects a file that no longer exists and it was about fixing something
                    // the fix may have removed the problematic file
                    if !std::path::Path::new(path).exists() {
                        // Only obsolete if this was a "file exists" condition for a problem indicator
                        // Not if it's a requirement for the fix
                        return Some(ObsolescenceReason::ConditionInvalid {
                            condition: format!("File no longer exists: {}", path),
                        });
                    }
                }
                super::Condition::PackageInstalled { name } => {
                    // Check if package version changed significantly
                    // Would integrate with package manager
                }
                _ => {}
            }
        }
        None
    }

    /// Register a CVE that might affect rules
    pub fn register_cve(&mut self, cve_id: &str, affected_packages: Vec<String>) {
        self.known_cves.insert(
            cve_id.to_string(),
            CveStatus {
                id: cve_id.to_string(),
                affected_packages,
                fixed_in: None,
                patched_locally: false,
                related_rule_ids: vec![],
            },
        );
        tracing::info!("Registered CVE: {}", cve_id);
    }

    /// Mark a CVE as fixed (upstream or locally)
    pub fn mark_cve_fixed(&mut self, cve_id: &str, fixed_version: Option<String>, local_patch: bool) {
        if let Some(status) = self.known_cves.get_mut(cve_id) {
            status.fixed_in = fixed_version.clone();
            status.patched_locally = local_patch;

            tracing::info!(
                "CVE {} marked as fixed{}",
                cve_id,
                if local_patch { " (local patch)" } else { " (upstream)" }
            );

            // Mark related rules for obsolescence review
            for rule_id in &status.related_rule_ids {
                self.health_cache.insert(
                    rule_id.clone(),
                    RuleHealth::PossiblyObsolete {
                        reason: format!("CVE {} has been fixed", cve_id),
                    },
                );
            }
        }
    }

    /// Get all proposals pending review
    pub fn pending_proposals(&self) -> Vec<&RuleProposal> {
        self.proposals
            .values()
            .filter(|p| p.status == ProposalStatus::PendingReview)
            .collect()
    }

    /// Get rules that need attention
    pub fn rules_needing_attention(&self) -> Vec<(&String, &RuleHealth)> {
        self.health_cache
            .iter()
            .filter(|(_, h)| !matches!(h, RuleHealth::Healthy | RuleHealth::Probationary { .. }))
            .collect()
    }

    /// Generate a lifecycle report
    pub fn generate_report(&self) -> LifecycleReport {
        let total_rules = self.health_cache.len();
        let healthy = self
            .health_cache
            .values()
            .filter(|h| matches!(h, RuleHealth::Healthy))
            .count();
        let degrading = self
            .health_cache
            .values()
            .filter(|h| matches!(h, RuleHealth::Degrading { .. }))
            .count();
        let needs_review = self
            .health_cache
            .values()
            .filter(|h| matches!(h, RuleHealth::NeedsReview { .. }))
            .count();
        let obsolete = self
            .health_cache
            .values()
            .filter(|h| matches!(h, RuleHealth::PossiblyObsolete { .. } | RuleHealth::Obsolete { .. }))
            .count();

        LifecycleReport {
            timestamp: chrono::Utc::now().to_rfc3339(),
            total_rules,
            healthy,
            degrading,
            needs_review,
            possibly_obsolete: obsolete,
            pending_proposals: self.pending_proposals().len(),
            tracked_cves: self.known_cves.len(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct LifecycleReport {
    pub timestamp: String,
    pub total_rules: usize,
    pub healthy: usize,
    pub degrading: usize,
    pub needs_review: usize,
    pub possibly_obsolete: usize,
    pub pending_proposals: usize,
    pub tracked_cves: usize,
}
