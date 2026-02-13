// SPDX-License-Identifier: PMPL-1.0-or-later
//! Ambient Payload - Ward UI layer data format.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Minimal, glanceable system state for the dock/tray indicator.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AmbientPayload {
    pub version: String,
    pub timestamp: DateTime<Utc>,
    pub indicator: Indicator,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub popover: Option<Popover>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notifications: Option<AmbientNotifications>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub schedule: Option<AmbientSchedule>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather_ref: Option<Uuid>,
}

/// Dock/tray indicator state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Indicator {
    pub state: AmbientState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<IndicatorIcon>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub badge: Option<Badge>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tooltip: Option<String>,
    #[serde(default = "default_animation")]
    pub animation: IndicatorAnimation,
}

fn default_animation() -> IndicatorAnimation {
    IndicatorAnimation::None
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AmbientState {
    Calm,
    Watch,
    Act,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum IndicatorIcon {
    Sun,
    Cloud,
    Storm,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum IndicatorAnimation {
    None,
    Pulse,
    Bounce,
    Glow,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Badge {
    #[serde(default)]
    pub show: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub count: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "type")]
    pub badge_type: Option<BadgeType>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BadgeType {
    Number,
    Dot,
    Exclamation,
}

/// Quick popover content (click on indicator).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Popover {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub headline: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subtext: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub metrics: Vec<PopoverMetric>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub quick_actions: Vec<QuickAction>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_scan: Option<LastScan>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PopoverMetric {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<MetricState>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trend: Option<MetricTrend>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MetricState {
    Good,
    Warning,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MetricTrend {
    Up,
    Down,
    Stable,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuickAction {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action: Option<QuickActionType>,
    #[serde(default)]
    pub primary: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QuickActionType {
    OpenDashboard,
    QuickScan,
    Dismiss,
    Snooze,
    Settings,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LastScan {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timestamp: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub relative: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AmbientNotifications {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub pending: Vec<PendingNotification>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cooldown: Option<NotificationCooldown>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingNotification {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "type")]
    pub notification_type: Option<PendingNotificationType>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub action_url: Option<String>,
    #[serde(default = "default_true")]
    pub dismissible: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_at: Option<DateTime<Utc>>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PendingNotificationType {
    Info,
    Warning,
    ActionRequired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationCooldown {
    #[serde(default)]
    pub active: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub until: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AmbientSchedule {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_scan: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scan_type: Option<ScanType>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_enabled: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ScanType {
    Quick,
    Standard,
    Deep,
}

impl AmbientPayload {
    /// Create a calm ambient payload.
    pub fn calm(tooltip: &str) -> Self {
        Self {
            version: "1.0.0".to_string(),
            timestamp: Utc::now(),
            indicator: Indicator {
                state: AmbientState::Calm,
                icon: Some(IndicatorIcon::Sun),
                color: Some("#4CAF50".to_string()),
                badge: None,
                tooltip: Some(tooltip.to_string()),
                animation: IndicatorAnimation::None,
            },
            popover: None,
            notifications: None,
            schedule: None,
            weather_ref: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ambient_payload_roundtrip() {
        let payload = AmbientPayload::calm("All systems nominal");
        let json = serde_json::to_string_pretty(&payload).unwrap();
        assert!(json.contains("calm"));
        assert!(json.contains("#4CAF50"));

        let parsed: AmbientPayload = serde_json::from_str(&json).unwrap();
        assert!(matches!(parsed.indicator.state, AmbientState::Calm));
    }

    #[test]
    fn test_ambient_payload_with_popover() {
        let mut payload = AmbientPayload::calm("All systems nominal");
        payload.popover = Some(Popover {
            headline: Some("System Healthy".to_string()),
            subtext: Some("Last scan 5 minutes ago".to_string()),
            metrics: vec![
                PopoverMetric {
                    label: Some("Disk".to_string()),
                    value: Some("45%".to_string()),
                    state: Some(MetricState::Good),
                    trend: Some(MetricTrend::Stable),
                },
            ],
            quick_actions: vec![
                QuickAction {
                    label: Some("Quick Scan".to_string()),
                    action: Some(QuickActionType::QuickScan),
                    primary: true,
                },
            ],
            last_scan: None,
        });

        let json = serde_json::to_string_pretty(&payload).unwrap();
        let parsed: AmbientPayload = serde_json::from_str(&json).unwrap();
        assert!(parsed.popover.is_some());
        assert_eq!(parsed.popover.unwrap().metrics.len(), 1);
    }
}
