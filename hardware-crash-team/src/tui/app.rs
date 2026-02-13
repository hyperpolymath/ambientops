// SPDX-License-Identifier: PMPL-1.0-or-later
//! TUI application state and event loop

use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::prelude::*;
use std::io;

use super::Screen;
use super::ui;
use crate::scanner;
use crate::types::*;

/// Application state
pub struct App {
    /// Current active screen
    pub screen: Screen,
    /// System report from last scan
    pub report: SystemReport,
    /// Selected device index in list
    pub selected_device: usize,
    /// Selected strategy index in plan builder
    pub selected_strategy: usize,
    /// Whether to quit
    pub should_quit: bool,
    /// Status message shown in footer
    pub status_message: String,
    /// Available remediation strategies
    pub strategies: Vec<&'static str>,
}

impl App {
    /// Create app with initial scan
    pub fn new() -> Result<Self> {
        let report = scanner::scan_system(true)?;
        let device_count = report.devices.len();
        let issue_count: usize = report.devices.iter()
            .map(|d| d.issues.len())
            .sum();

        Ok(Self {
            screen: Screen::StatusDashboard,
            report,
            selected_device: 0,
            selected_strategy: 0,
            should_quit: false,
            status_message: format!(
                "Scan complete: {} devices, {} issues. Press ? for help.",
                device_count, issue_count
            ),
            strategies: vec!["pci-stub", "vfio-pci", "dual", "power-off", "disable", "unbind"],
        })
    }

    /// Handle key event
    pub fn handle_key(&mut self, key: KeyEvent) {
        // Global keys
        match key.code {
            KeyCode::Char('q') | KeyCode::Esc => {
                if self.screen != Screen::DeviceList {
                    self.screen = Screen::DeviceList;
                    self.status_message = "Returned to device list.".to_string();
                } else {
                    self.should_quit = true;
                }
            }
            KeyCode::Tab => {
                if key.modifiers.contains(KeyModifiers::SHIFT) {
                    self.screen = self.screen.prev();
                } else {
                    self.screen = self.screen.next();
                }
                self.status_message = format!("Screen: {}", self.screen.title());
            }
            KeyCode::Char('r') => {
                self.refresh_scan();
            }
            KeyCode::Char('?') => {
                self.status_message = "q:Quit Tab:Screens ↑↓:Navigate Enter:Select p:Plan d:Diagnose r:Refresh".to_string();
            }
            _ => {
                // Screen-specific keys
                self.handle_screen_key(key);
            }
        }
    }

    fn handle_screen_key(&mut self, key: KeyEvent) {
        match self.screen {
            Screen::DeviceList => self.handle_device_list_key(key),
            Screen::DeviceDetail => self.handle_device_detail_key(key),
            Screen::PlanBuilder => self.handle_plan_builder_key(key),
            Screen::DiagnosisView => {} // Read-only
            Screen::StatusDashboard => {} // Read-only
        }
    }

    fn handle_device_list_key(&mut self, key: KeyEvent) {
        let device_count = self.report.devices.len();
        if device_count == 0 { return; }

        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                if self.selected_device > 0 {
                    self.selected_device -= 1;
                }
            }
            KeyCode::Down | KeyCode::Char('j') => {
                if self.selected_device < device_count - 1 {
                    self.selected_device += 1;
                }
            }
            KeyCode::Home => self.selected_device = 0,
            KeyCode::End => self.selected_device = device_count - 1,
            KeyCode::Enter => {
                self.screen = Screen::DeviceDetail;
                let dev = &self.report.devices[self.selected_device];
                self.status_message = format!("Viewing: {} ({})", dev.slot, dev.pci_id);
            }
            KeyCode::Char('p') => {
                self.screen = Screen::PlanBuilder;
                let dev = &self.report.devices[self.selected_device];
                self.status_message = format!(
                    "Plan builder for: {} — select strategy with ↑↓, Enter to generate.",
                    dev.slot
                );
            }
            KeyCode::Char('d') => {
                self.screen = Screen::DiagnosisView;
                self.status_message = "Diagnosis view (read-only).".to_string();
            }
            _ => {}
        }
    }

    fn handle_device_detail_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Char('p') => {
                self.screen = Screen::PlanBuilder;
                let dev = &self.report.devices[self.selected_device];
                self.status_message = format!("Plan builder for: {}", dev.slot);
            }
            _ => {}
        }
    }

    fn handle_plan_builder_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => {
                if self.selected_strategy > 0 {
                    self.selected_strategy -= 1;
                }
            }
            KeyCode::Down | KeyCode::Char('j') => {
                if self.selected_strategy < self.strategies.len() - 1 {
                    self.selected_strategy += 1;
                }
            }
            KeyCode::Enter => {
                let dev = &self.report.devices[self.selected_device];
                let strategy = self.strategies[self.selected_strategy];
                self.status_message = format!(
                    "Plan generated: {} for {} — use CLI `hardware-crash-team plan {} --strategy {}` to apply.",
                    strategy, dev.slot, dev.slot, strategy
                );
            }
            _ => {}
        }
    }

    fn refresh_scan(&mut self) {
        match scanner::scan_system(true) {
            Ok(report) => {
                let device_count = report.devices.len();
                let issue_count: usize = report.devices.iter()
                    .map(|d| d.issues.len())
                    .sum();
                self.report = report;
                self.selected_device = 0;
                self.status_message = format!(
                    "Refreshed: {} devices, {} issues.",
                    device_count, issue_count
                );
            }
            Err(e) => {
                self.status_message = format!("Refresh failed: {}", e);
            }
        }
    }

    /// Get currently selected device
    pub fn selected_device(&self) -> Option<&PciDevice> {
        self.report.devices.get(self.selected_device)
    }
}

/// Run the TUI application
pub fn run() -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app
    let mut app = App::new()?;

    // Event loop
    loop {
        terminal.draw(|frame| ui::render(frame, &app))?;

        if event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                app.handle_key(key);
            }
        }

        if app.should_quit {
            break;
        }
    }

    // Restore terminal
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    Ok(())
}
