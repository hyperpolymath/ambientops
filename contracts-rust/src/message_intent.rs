// SPDX-License-Identifier: PMPL-1.0-or-later
//! Message Intent - feedback-a-tron message request format.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// How tools request messages via feedback-a-tron.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageIntent {
    pub version: String,
    pub intent_id: Uuid,
    pub created_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_tool: Option<String>,
    pub audience: IntentAudience,
    pub content: IntentContent,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachments: Vec<IntentAttachment>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub redaction: Option<IntentRedaction>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub routing: Option<IntentRouting>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<IntentContext>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user_approval: Option<UserApproval>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum IntentAudience {
    User,
    Helper,
    Forum,
    Vendor,
    Support,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentContent {
    pub subject: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    #[serde(default = "default_body_format", skip_serializing_if = "is_text")]
    pub body_format: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template_vars: Option<serde_json::Value>,
}

fn default_body_format() -> String {
    "text".to_string()
}

fn is_text(s: &str) -> bool {
    s == "text"
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentAttachment {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attachment_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub filename: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mime_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<AttachmentSource>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub redaction_profile: Option<RedactionLevel>,
    #[serde(default = "default_true")]
    pub include_by_default: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AttachmentSource {
    Envelope,
    Receipt,
    Log,
    Screenshot,
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RedactionLevel {
    None,
    Minimal,
    Standard,
    Maximum,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentRedaction {
    #[serde(default = "default_standard")]
    pub profile: RedactionLevel,
    #[serde(default = "default_true")]
    pub redact_hostname: bool,
    #[serde(default = "default_true")]
    pub redact_username: bool,
    #[serde(default = "default_true")]
    pub redact_paths: bool,
    #[serde(default = "default_true")]
    pub redact_ips: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub custom_patterns: Vec<RedactionPattern>,
}

fn default_standard() -> RedactionLevel {
    RedactionLevel::Standard
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RedactionPattern {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pattern: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub replacement: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentRouting {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub targets: Vec<RoutingTarget>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub severity: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub priority: Option<String>,
    #[serde(default)]
    pub requires_response: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_deadline: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingTarget {
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "type")]
    pub target_type: Option<TargetType>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub address: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TargetType {
    Email,
    ForumPost,
    Ticket,
    Chat,
    Clipboard,
    File,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentContext {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub envelope_ref: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub receipt_ref: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub related_messages: Vec<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserApproval {
    #[serde(default = "default_true")]
    pub required: bool,
    #[serde(default = "default_true")]
    pub preview_required: bool,
    #[serde(default = "default_true")]
    pub edit_allowed: bool,
}

impl MessageIntent {
    /// Create a new message intent with required fields.
    pub fn new(audience: IntentAudience, subject: &str) -> Self {
        Self {
            version: "1.0.0".to_string(),
            intent_id: Uuid::new_v4(),
            created_at: Utc::now(),
            source_tool: None,
            audience,
            content: IntentContent {
                subject: subject.to_string(),
                body: None,
                body_format: "text".to_string(),
                template: None,
                template_vars: None,
            },
            attachments: Vec::new(),
            redaction: None,
            routing: None,
            context: None,
            user_approval: Some(UserApproval {
                required: true,
                preview_required: true,
                edit_allowed: true,
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_intent_roundtrip() {
        let intent = MessageIntent::new(IntentAudience::User, "Disk space warning");
        let json = serde_json::to_string_pretty(&intent).unwrap();
        assert!(json.contains("Disk space warning"));

        let parsed: MessageIntent = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.intent_id, intent.intent_id);
        assert!(matches!(parsed.audience, IntentAudience::User));
    }

    #[test]
    fn test_message_intent_with_routing() {
        let mut intent = MessageIntent::new(IntentAudience::Support, "Hardware failure report");
        intent.routing = Some(IntentRouting {
            targets: vec![RoutingTarget {
                target_type: Some(TargetType::Email),
                address: Some("support@example.com".to_string()),
                label: Some("Support Team".to_string()),
            }],
            tags: vec!["hardware".to_string(), "urgent".to_string()],
            severity: Some("high".to_string()),
            priority: Some("urgent".to_string()),
            requires_response: true,
            response_deadline: None,
        });

        let json = serde_json::to_string_pretty(&intent).unwrap();
        let parsed: MessageIntent = serde_json::from_str(&json).unwrap();
        assert!(parsed.routing.is_some());
        assert_eq!(parsed.routing.unwrap().tags.len(), 2);
    }
}
