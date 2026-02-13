// SPDX-License-Identifier: PMPL-1.0-or-later
//! Core types for hardware-crash-team

use serde::{Deserialize, Serialize};

/// Full system hardware scan report
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemReport {
    /// Scan timestamp
    pub timestamp: String,
    /// Kernel version
    pub kernel_version: String,
    /// All PCI devices found
    pub devices: Vec<PciDevice>,
    /// IOMMU status
    pub iommu: IommuStatus,
    /// ACPI errors detected
    pub acpi_errors: Vec<AcpiError>,
    /// Overall risk assessment
    pub risk_level: RiskLevel,
}

/// A PCI device and its status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PciDevice {
    /// PCI slot (e.g., "01:00.0")
    pub slot: String,
    /// Vendor:Device ID (e.g., "10de:13b0")
    pub pci_id: String,
    /// Human-readable description
    pub description: String,
    /// Vendor name
    pub vendor: String,
    /// Device class (e.g., "VGA compatible controller", "Audio device")
    pub class: String,
    /// Current driver bound (if any)
    pub driver: Option<String>,
    /// Available kernel modules
    pub kernel_modules: Vec<String>,
    /// Power state (D0, D1, D2, D3hot, D3cold)
    pub power_state: PowerState,
    /// Whether device is enabled
    pub enabled: bool,
    /// IOMMU group
    pub iommu_group: Option<u32>,
    /// Memory regions (BAR)
    pub memory_regions: Vec<MemoryRegion>,
    /// Issues detected with this device
    pub issues: Vec<DeviceIssue>,
}

/// PCI device power state
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PowerState {
    D0,       // Full power
    D1,       // Light sleep
    D2,       // Deeper sleep
    D3Hot,    // Software-managed off
    D3Cold,   // Hardware-managed off
    Unknown,
}

/// A memory region (BAR) mapped by a PCI device
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryRegion {
    /// BAR index
    pub index: u8,
    /// Base address
    pub address: String,
    /// Size in bytes
    pub size: u64,
    /// Whether prefetchable
    pub prefetchable: bool,
    /// Bit width (32 or 64)
    pub width: u8,
}

/// Issue detected with a PCI device
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceIssue {
    /// Issue severity
    pub severity: IssueSeverity,
    /// Issue type
    pub issue_type: IssueType,
    /// Human-readable description
    pub description: String,
    /// Recommended remediation
    pub remediation: String,
}

/// Issue severity levels
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Ord, PartialOrd, Eq)]
pub enum IssueSeverity {
    Info,
    Warning,
    High,
    Critical,
}

/// Types of hardware issues
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IssueType {
    /// Device powered on with no driver managing it
    ZombieDevice,
    /// Driver loaded but failed verification
    TaintedDriver,
    /// Partial driver binding (e.g., audio codec on GPU)
    PartialBinding,
    /// Device generating interrupts with no handler
    SpuriousInterrupts,
    /// ACPI method errors related to device
    AcpiError,
    /// Device not in IOMMU group (no DMA isolation)
    NoIommuIsolation,
    /// Driver blacklisted but device still active
    BlacklistedButActive,
    /// Memory regions mapped with no driver managing them
    UnmanagedMemory,
    /// Power state conflict
    PowerStateConflict,
}

/// Overall system risk assessment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RiskLevel {
    /// No hardware issues detected
    Clean,
    /// Minor issues, unlikely to cause crashes
    Low,
    /// Issues present that could cause instability
    Medium,
    /// Active issues likely causing crashes
    High,
    /// Critical hardware state, crashes expected
    Critical,
}

/// IOMMU status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IommuStatus {
    /// Whether IOMMU is enabled
    pub enabled: bool,
    /// IOMMU type (Intel VT-d, AMD-Vi)
    pub iommu_type: Option<String>,
    /// Number of IOMMU groups
    pub group_count: u32,
    /// Interrupt remapping enabled
    pub interrupt_remapping: bool,
}

/// ACPI error from system logs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AcpiError {
    /// ACPI method path (e.g., "_SB._OSC")
    pub method: String,
    /// Error code
    pub error_code: String,
    /// Human-readable description
    pub description: String,
    /// Related PCI device (if identifiable)
    pub related_device: Option<String>,
}

/// Crash log analysis result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrashDiagnosis {
    /// Number of boots analyzed
    pub boots_analyzed: usize,
    /// Crashes found
    pub crashes: Vec<CrashEvent>,
    /// Hardware correlations
    pub correlations: Vec<HardwareCorrelation>,
    /// Confidence score (0.0 to 1.0)
    pub confidence: f64,
    /// Primary suspect device
    pub primary_suspect: Option<String>,
    /// Recommended action
    pub recommendation: String,
}

/// A crash event from logs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrashEvent {
    /// Boot identifier
    pub boot_id: String,
    /// Timestamp
    pub timestamp: String,
    /// Duration of session before crash (seconds)
    pub session_duration: u64,
    /// Crash indicators found
    pub indicators: Vec<String>,
    /// Related hardware events
    pub hardware_events: Vec<String>,
}

/// Correlation between hardware events and crashes
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HardwareCorrelation {
    /// Device involved
    pub device: String,
    /// Event type
    pub event: String,
    /// How many crashes it correlates with
    pub crash_count: usize,
    /// Correlation strength (0.0 to 1.0)
    pub strength: f64,
}

/// A remediation plan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemediationPlan {
    /// Plan ID
    pub id: String,
    /// Target device
    pub device: String,
    /// Strategy name
    pub strategy: RemediationStrategy,
    /// Steps to execute
    pub steps: Vec<RemediationStep>,
    /// Undo steps (reverse order)
    pub undo_steps: Vec<RemediationStep>,
    /// Requires reboot
    pub requires_reboot: bool,
    /// Estimated risk of the remediation itself
    pub risk: RiskLevel,
}

/// Remediation strategies
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RemediationStrategy {
    /// Claim device with pci-stub (kernel builtin null driver)
    PciStub,
    /// Claim device with vfio-pci (IOMMU-backed isolation)
    VfioPci,
    /// Both pci-stub and vfio-pci for belt-and-braces
    DualNullDriver,
    /// Power off device via ACPI
    AcpiPowerOff,
    /// Disable device in sysfs
    SysfsDisable,
    /// Unbind current driver
    DriverUnbind,
}

impl RemediationStrategy {
    /// Whether this strategy requires a reboot to take effect
    pub fn requires_reboot(&self) -> bool {
        matches!(self, Self::PciStub | Self::VfioPci | Self::DualNullDriver)
    }

    /// Risk level for this strategy
    pub fn risk_level(&self) -> RiskLevel {
        match self {
            Self::AcpiPowerOff => RiskLevel::Medium,
            _ => RiskLevel::Low,
        }
    }
}

/// A multi-device remediation plan wrapping per-device plans
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultiDevicePlan {
    /// Plan ID
    pub id: String,
    /// All target devices
    pub devices: Vec<String>,
    /// Per-device (or combined) plans
    pub plans: Vec<RemediationPlan>,
    /// Whether the overall plan requires reboot
    pub requires_reboot: bool,
    /// Overall risk level
    pub risk: RiskLevel,
}

/// A single remediation step
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemediationStep {
    /// Step description
    pub description: String,
    /// Command to execute
    pub command: String,
    /// Whether this step needs sudo
    pub needs_sudo: bool,
    /// Whether this step needs a reboot to take effect
    pub needs_reboot: bool,
}

/// Receipt from applying a remediation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemediationReceipt {
    /// Plan that was applied
    pub plan: RemediationPlan,
    /// Timestamp of application
    pub applied_at: String,
    /// Whether reboot is pending
    pub reboot_pending: bool,
    /// Pre-apply device state (for undo verification)
    pub pre_state: String,
}
