// SPDX-License-Identifier: PMPL-1.0-or-later
//! ATS2 TUI — interactive terminal interface for hardware diagnostics
//!
//! Provides 5 screens:
//! 1. Device List — table of PCI devices with issues color-coded
//! 2. Device Detail — full info on selected device
//! 3. Plan Builder — select strategy and preview plan
//! 4. Diagnosis View — crash analysis and correlations
//! 5. Status Dashboard — system overview
//!
//! Requires `tui` feature: `cargo build --features tui`

#[cfg(feature = "tui")]
mod app;
#[cfg(feature = "tui")]
mod ui;

#[cfg(feature = "tui")]
pub use app::run;

#[cfg(not(feature = "tui"))]
pub fn run() -> anyhow::Result<()> {
    println!("TUI requires the 'tui' feature.");
    println!("Build with: cargo build -p hardware-crash-team --features tui");
    Ok(())
}

/// Screen identifiers
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Screen {
    DeviceList,
    DeviceDetail,
    PlanBuilder,
    DiagnosisView,
    StatusDashboard,
}

impl Screen {
    /// Cycle to next screen
    pub fn next(self) -> Self {
        match self {
            Self::DeviceList => Self::DeviceDetail,
            Self::DeviceDetail => Self::PlanBuilder,
            Self::PlanBuilder => Self::DiagnosisView,
            Self::DiagnosisView => Self::StatusDashboard,
            Self::StatusDashboard => Self::DeviceList,
        }
    }

    /// Cycle to previous screen
    pub fn prev(self) -> Self {
        match self {
            Self::DeviceList => Self::StatusDashboard,
            Self::DeviceDetail => Self::DeviceList,
            Self::PlanBuilder => Self::DeviceDetail,
            Self::DiagnosisView => Self::PlanBuilder,
            Self::StatusDashboard => Self::DiagnosisView,
        }
    }

    /// Screen title
    pub fn title(self) -> &'static str {
        match self {
            Self::DeviceList => "Device List",
            Self::DeviceDetail => "Device Detail",
            Self::PlanBuilder => "Plan Builder",
            Self::DiagnosisView => "Diagnosis",
            Self::StatusDashboard => "Status Dashboard",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_screen_cycle_next() {
        let s = Screen::DeviceList;
        assert_eq!(s.next(), Screen::DeviceDetail);
        assert_eq!(s.next().next(), Screen::PlanBuilder);
        assert_eq!(s.next().next().next(), Screen::DiagnosisView);
        assert_eq!(s.next().next().next().next(), Screen::StatusDashboard);
        assert_eq!(s.next().next().next().next().next(), Screen::DeviceList);
    }

    #[test]
    fn test_screen_cycle_prev() {
        let s = Screen::DeviceList;
        assert_eq!(s.prev(), Screen::StatusDashboard);
        assert_eq!(s.prev().prev(), Screen::DiagnosisView);
    }

    #[test]
    fn test_screen_titles() {
        assert_eq!(Screen::DeviceList.title(), "Device List");
        assert_eq!(Screen::PlanBuilder.title(), "Plan Builder");
        assert_eq!(Screen::StatusDashboard.title(), "Status Dashboard");
    }

    #[test]
    fn test_screen_roundtrip() {
        // 5 nexts should return to start
        let mut s = Screen::DeviceList;
        for _ in 0..5 {
            s = s.next();
        }
        assert_eq!(s, Screen::DeviceList);
    }

    #[cfg(not(feature = "tui"))]
    #[test]
    fn test_run_without_feature() {
        // Should succeed and print message
        assert!(run().is_ok());
    }
}
