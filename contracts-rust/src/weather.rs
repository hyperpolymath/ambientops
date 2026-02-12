// SPDX-License-Identifier: PMPL-1.0-or-later
//! System Weather - Ward ambient UI payload.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Ward ambient UI payload showing system health state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemWeather {
    pub version: String,
    pub timestamp: DateTime<Utc>,
    pub state: WeatherState,
    pub summary: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub categories: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub evidence_pointers: Vec<EvidencePointer>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notifications: Option<NotificationConfig>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<SuggestedAction>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trends: Option<Trends>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<WeatherSource>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum WeatherState {
    Calm,
    Watch,
    Act,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidencePointer {
    #[serde(rename = "type")]
    pub pointer_type: EvidenceType,
    #[serde(rename = "ref")]
    pub reference: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EvidenceType {
    Envelope,
    Finding,
    Metric,
    Log,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationConfig {
    #[serde(default)]
    pub should_notify: bool,
    #[serde(default = "default_notification_type")]
    pub notification_type: NotificationType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cooldown_until: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub snooze_options: Vec<SnoozeOption>,
}

fn default_notification_type() -> NotificationType {
    NotificationType::Silent
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NotificationType {
    Silent,
    Badge,
    Toast,
    Alert,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnoozeOption {
    pub label: String,
    pub duration_seconds: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestedAction {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action_id: Option<String>,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub priority: Option<ActionPriority>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub handler: Option<ActionHandler>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parameters: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ActionPriority {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionHandler {
    OpenTheatre,
    OpenAAndE,
    OpenPsa,
    OpenSettings,
    Dismiss,
    Snooze,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Trends {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disk_usage: Option<Trend>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_pressure: Option<Trend>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cpu_load: Option<Trend>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub overall: Option<Trend>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Trend {
    pub direction: TrendDirection,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rate: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub forecast: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TrendDirection {
    Improving,
    Stable,
    Degrading,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeatherSource {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_scan: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_scan: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scan_profile: Option<String>,
}

impl SystemWeather {
    /// Create a calm weather report.
    pub fn calm(summary: &str) -> Self {
        Self {
            version: "1.0.0".to_string(),
            timestamp: Utc::now(),
            state: WeatherState::Calm,
            summary: summary.to_string(),
            details: None,
            categories: None,
            evidence_pointers: Vec::new(),
            notifications: None,
            actions: Vec::new(),
            trends: None,
            source: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_weather_serialization() {
        let weather = SystemWeather::calm("All systems nominal");

        let json = serde_json::to_string_pretty(&weather).unwrap();
        assert!(json.contains("calm"));
        assert!(json.contains("All systems nominal"));

        let parsed: SystemWeather = serde_json::from_str(&json).unwrap();
        assert!(matches!(parsed.state, WeatherState::Calm));
    }
}
