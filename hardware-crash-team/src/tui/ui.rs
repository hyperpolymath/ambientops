// SPDX-License-Identifier: PMPL-1.0-or-later
//! TUI rendering — ratatui widgets for each screen

use ratatui::prelude::*;
use ratatui::widgets::*;

use super::Screen;
use super::app::App;
use crate::types::*;

/// Main render function dispatching to screen-specific renderers
pub fn render(frame: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),   // Header
            Constraint::Min(10),     // Main content
            Constraint::Length(3),   // Footer/status
        ])
        .split(frame.area());

    render_header(frame, chunks[0], app);

    match app.screen {
        Screen::DeviceList => render_device_list(frame, chunks[1], app),
        Screen::DeviceDetail => render_device_detail(frame, chunks[1], app),
        Screen::PlanBuilder => render_plan_builder(frame, chunks[1], app),
        Screen::DiagnosisView => render_diagnosis(frame, chunks[1], app),
        Screen::StatusDashboard => render_status_dashboard(frame, chunks[1], app),
    }

    render_footer(frame, chunks[2], app);
}

fn render_header(frame: &mut Frame, area: Rect, app: &App) {
    let tabs: Vec<Line> = [
        Screen::DeviceList,
        Screen::DeviceDetail,
        Screen::PlanBuilder,
        Screen::DiagnosisView,
        Screen::StatusDashboard,
    ]
    .iter()
    .map(|s| {
        if *s == app.screen {
            Line::from(Span::styled(
                format!(" {} ", s.title()),
                Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD),
            ))
        } else {
            Line::from(Span::styled(
                format!(" {} ", s.title()),
                Style::default().fg(Color::DarkGray),
            ))
        }
    })
    .collect();

    let tabs_widget = Tabs::new(tabs)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(" Hardware Crash Team — ATS2 TUI ")
            .title_style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)))
        .select(match app.screen {
            Screen::DeviceList => 0,
            Screen::DeviceDetail => 1,
            Screen::PlanBuilder => 2,
            Screen::DiagnosisView => 3,
            Screen::StatusDashboard => 4,
        })
        .highlight_style(Style::default().fg(Color::Yellow));

    frame.render_widget(tabs_widget, area);
}

fn render_footer(frame: &mut Frame, area: Rect, app: &App) {
    let footer = Paragraph::new(app.status_message.clone())
        .block(Block::default()
            .borders(Borders::ALL)
            .title(" Status ")
            .border_style(Style::default().fg(Color::DarkGray)));

    frame.render_widget(footer, area);
}

// === Screen: Device List ===

fn render_device_list(frame: &mut Frame, area: Rect, app: &App) {
    let header_cells = ["Slot", "PCI ID", "Driver", "Power", "Issues", "Risk"]
        .iter()
        .map(|h| Cell::from(*h).style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)));
    let header = Row::new(header_cells).height(1);

    let rows: Vec<Row> = app.report.devices.iter().enumerate().map(|(idx, dev)| {
        let issue_count = dev.issues.len();
        let max_severity = dev.issues.iter()
            .map(|i| &i.severity)
            .max()
            .cloned();

        let row_style = if idx == app.selected_device {
            Style::default().bg(Color::DarkGray)
        } else {
            Style::default()
        };

        let risk_color = match &max_severity {
            Some(IssueSeverity::Critical) => Color::Red,
            Some(IssueSeverity::High) => Color::LightRed,
            Some(IssueSeverity::Warning) => Color::Yellow,
            Some(IssueSeverity::Info) => Color::Green,
            None => Color::Green,
        };

        let risk_text = match &max_severity {
            Some(s) => format!("{:?}", s),
            None => "Clean".to_string(),
        };

        Row::new(vec![
            Cell::from(dev.slot.clone()),
            Cell::from(dev.pci_id.clone()),
            Cell::from(dev.driver.clone().unwrap_or_else(|| "(none)".to_string())),
            Cell::from(format_power_state(&dev.power_state)),
            Cell::from(format!("{}", issue_count)),
            Cell::from(risk_text).style(Style::default().fg(risk_color)),
        ])
        .style(row_style)
    }).collect();

    let table = Table::new(
        rows,
        [
            Constraint::Length(10),
            Constraint::Length(12),
            Constraint::Length(20),
            Constraint::Length(8),
            Constraint::Length(8),
            Constraint::Length(10),
        ],
    )
    .header(header)
    .block(Block::default()
        .borders(Borders::ALL)
        .title(format!(" Devices ({}) ", app.report.devices.len()))
        .title_style(Style::default().fg(Color::White)))
    .row_highlight_style(Style::default().bg(Color::DarkGray));

    frame.render_widget(table, area);
}

// === Screen: Device Detail ===

fn render_device_detail(frame: &mut Frame, area: Rect, app: &App) {
    let dev = match app.selected_device() {
        Some(d) => d,
        None => {
            let msg = Paragraph::new("No device selected. Go to Device List and select one.")
                .block(Block::default().borders(Borders::ALL).title(" Device Detail "));
            frame.render_widget(msg, area);
            return;
        }
    };

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(10), // Info block
            Constraint::Min(5),    // Issues + BARs
        ])
        .split(area);

    // Device info
    let info_text = vec![
        Line::from(vec![
            Span::styled("Slot: ", Style::default().fg(Color::Yellow)),
            Span::raw(&dev.slot),
        ]),
        Line::from(vec![
            Span::styled("PCI ID: ", Style::default().fg(Color::Yellow)),
            Span::raw(&dev.pci_id),
        ]),
        Line::from(vec![
            Span::styled("Description: ", Style::default().fg(Color::Yellow)),
            Span::raw(if dev.description.is_empty() { "(unknown)" } else { &dev.description }),
        ]),
        Line::from(vec![
            Span::styled("Class: ", Style::default().fg(Color::Yellow)),
            Span::raw(&dev.class),
        ]),
        Line::from(vec![
            Span::styled("Driver: ", Style::default().fg(Color::Yellow)),
            Span::raw(dev.driver.as_deref().unwrap_or("(none)")),
        ]),
        Line::from(vec![
            Span::styled("Power: ", Style::default().fg(Color::Yellow)),
            Span::raw(format_power_state(&dev.power_state)),
        ]),
        Line::from(vec![
            Span::styled("IOMMU Group: ", Style::default().fg(Color::Yellow)),
            Span::raw(dev.iommu_group.map_or("(none)".to_string(), |g| g.to_string())),
        ]),
        Line::from(vec![
            Span::styled("Enabled: ", Style::default().fg(Color::Yellow)),
            Span::raw(if dev.enabled { "yes" } else { "no" }),
        ]),
    ];

    let info = Paragraph::new(info_text)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(format!(" {} — {} ", dev.slot, dev.pci_id)));
    frame.render_widget(info, chunks[0]);

    // Issues + BARs
    let lower = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(chunks[1]);

    // Issues
    let issue_lines: Vec<Line> = if dev.issues.is_empty() {
        vec![Line::styled("  No issues detected.", Style::default().fg(Color::Green))]
    } else {
        dev.issues.iter().map(|issue| {
            let color = match issue.severity {
                IssueSeverity::Critical => Color::Red,
                IssueSeverity::High => Color::LightRed,
                IssueSeverity::Warning => Color::Yellow,
                IssueSeverity::Info => Color::Green,
            };
            Line::from(vec![
                Span::styled(format!("[{:?}] ", issue.severity), Style::default().fg(color)),
                Span::raw(&issue.description),
            ])
        }).collect()
    };

    let issues = Paragraph::new(issue_lines)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(format!(" Issues ({}) ", dev.issues.len())));
    frame.render_widget(issues, lower[0]);

    // Memory regions (BARs)
    let bar_lines: Vec<Line> = if dev.memory_regions.is_empty() {
        vec![Line::styled("  No memory regions.", Style::default().fg(Color::DarkGray))]
    } else {
        dev.memory_regions.iter().map(|bar| {
            Line::from(format!(
                "  BAR{}: {} ({} bytes, {}bit{})",
                bar.index,
                bar.address,
                bar.size,
                bar.width,
                if bar.prefetchable { ", prefetch" } else { "" },
            ))
        }).collect()
    };

    let bars = Paragraph::new(bar_lines)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(format!(" BARs ({}) ", dev.memory_regions.len())));
    frame.render_widget(bars, lower[1]);
}

// === Screen: Plan Builder ===

fn render_plan_builder(frame: &mut Frame, area: Rect, app: &App) {
    let dev = match app.selected_device() {
        Some(d) => d,
        None => {
            let msg = Paragraph::new("No device selected.")
                .block(Block::default().borders(Borders::ALL).title(" Plan Builder "));
            frame.render_widget(msg, area);
            return;
        }
    };

    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(40), Constraint::Percentage(60)])
        .split(area);

    // Strategy list
    let items: Vec<ListItem> = app.strategies.iter().enumerate().map(|(idx, s)| {
        let style = if idx == app.selected_strategy {
            Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)
        } else {
            Style::default()
        };
        let prefix = if idx == app.selected_strategy { "▸ " } else { "  " };
        ListItem::new(format!("{}{}", prefix, s)).style(style)
    }).collect();

    let strategy_list = List::new(items)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(format!(" Strategy for {} ", dev.slot)));
    frame.render_widget(strategy_list, chunks[0]);

    // Strategy description
    let desc = strategy_description(app.strategies[app.selected_strategy]);
    let preview = Paragraph::new(desc)
        .wrap(Wrap { trim: true })
        .block(Block::default()
            .borders(Borders::ALL)
            .title(" Strategy Details "));
    frame.render_widget(preview, chunks[1]);
}

fn strategy_description(name: &str) -> Vec<Line<'static>> {
    match name {
        "pci-stub" => vec![
            Line::styled("PCI Stub Driver", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Line::raw(""),
            Line::raw("Claims device with kernel builtin null driver."),
            Line::raw("Uses rpm-ostree kargs to add pci-stub.ids."),
            Line::raw(""),
            Line::from(vec![
                Span::styled("Risk: ", Style::default().fg(Color::Yellow)),
                Span::styled("Low", Style::default().fg(Color::Green)),
            ]),
            Line::from(vec![
                Span::styled("Reboot: ", Style::default().fg(Color::Yellow)),
                Span::raw("Required"),
            ]),
            Line::raw(""),
            Line::raw("Reversible via rpm-ostree kargs --delete."),
        ],
        "vfio-pci" => vec![
            Line::styled("VFIO-PCI Isolation", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Line::raw(""),
            Line::raw("Claims device with IOMMU-backed vfio-pci driver."),
            Line::raw("Provides full DMA isolation via IOMMU."),
            Line::raw(""),
            Line::from(vec![
                Span::styled("Risk: ", Style::default().fg(Color::Yellow)),
                Span::styled("Low", Style::default().fg(Color::Green)),
            ]),
            Line::from(vec![
                Span::styled("Reboot: ", Style::default().fg(Color::Yellow)),
                Span::raw("Required"),
            ]),
            Line::raw(""),
            Line::raw("Best for devices that need passthrough later."),
        ],
        "dual" => vec![
            Line::styled("Dual Null Driver (Belt & Braces)", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Line::raw(""),
            Line::raw("Both pci-stub and vfio-pci claim the device."),
            Line::raw("Maximum protection against driver rebinding."),
            Line::raw(""),
            Line::from(vec![
                Span::styled("Risk: ", Style::default().fg(Color::Yellow)),
                Span::styled("Low", Style::default().fg(Color::Green)),
            ]),
            Line::from(vec![
                Span::styled("Reboot: ", Style::default().fg(Color::Yellow)),
                Span::raw("Required"),
            ]),
            Line::raw(""),
            Line::raw("Recommended for zombie devices causing crashes."),
        ],
        "power-off" => vec![
            Line::styled("ACPI Power Off", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Line::raw(""),
            Line::raw("Powers down and removes device via ACPI/sysfs."),
            Line::raw("Immediate effect, no reboot needed."),
            Line::raw(""),
            Line::from(vec![
                Span::styled("Risk: ", Style::default().fg(Color::Yellow)),
                Span::styled("Medium", Style::default().fg(Color::Yellow)),
            ]),
            Line::from(vec![
                Span::styled("Reboot: ", Style::default().fg(Color::Yellow)),
                Span::raw("Not required"),
            ]),
            Line::raw(""),
            Line::raw("Undo via PCI bus rescan."),
        ],
        "disable" => vec![
            Line::styled("Sysfs Disable", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Line::raw(""),
            Line::raw("Disables device by writing 0 to sysfs enable."),
            Line::raw("Immediate effect, no reboot needed."),
            Line::raw(""),
            Line::from(vec![
                Span::styled("Risk: ", Style::default().fg(Color::Yellow)),
                Span::styled("Low", Style::default().fg(Color::Green)),
            ]),
            Line::from(vec![
                Span::styled("Reboot: ", Style::default().fg(Color::Yellow)),
                Span::raw("Not required"),
            ]),
            Line::raw(""),
            Line::raw("Reversible by writing 1 to enable."),
        ],
        "unbind" => vec![
            Line::styled("Driver Unbind", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Line::raw(""),
            Line::raw("Unbinds current driver from the device."),
            Line::raw("Requires a driver to be currently bound."),
            Line::raw(""),
            Line::from(vec![
                Span::styled("Risk: ", Style::default().fg(Color::Yellow)),
                Span::styled("Low", Style::default().fg(Color::Green)),
            ]),
            Line::from(vec![
                Span::styled("Reboot: ", Style::default().fg(Color::Yellow)),
                Span::raw("Not required"),
            ]),
            Line::raw(""),
            Line::raw("Reversible by writing slot to driver bind."),
        ],
        _ => vec![Line::raw("Unknown strategy.")],
    }
}

// === Screen: Diagnosis View ===

fn render_diagnosis(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(6),  // Summary
            Constraint::Min(5),    // Details
        ])
        .split(area);

    let issue_count: usize = app.report.devices.iter()
        .map(|d| d.issues.len())
        .sum();
    let problem_devices: Vec<&PciDevice> = app.report.devices.iter()
        .filter(|d| !d.issues.is_empty())
        .collect();

    let summary = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("Total Devices: ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{}", app.report.devices.len())),
        ]),
        Line::from(vec![
            Span::styled("Devices with Issues: ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{}", problem_devices.len())),
        ]),
        Line::from(vec![
            Span::styled("Total Issues: ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{}", issue_count)),
        ]),
        Line::from(vec![
            Span::styled("Risk Level: ", Style::default().fg(Color::Yellow)),
            Span::styled(
                format!("{:?}", app.report.risk_level),
                risk_style(&app.report.risk_level),
            ),
        ]),
    ])
    .block(Block::default()
        .borders(Borders::ALL)
        .title(" Diagnosis Summary "));
    frame.render_widget(summary, chunks[0]);

    // Problem device details
    let mut lines: Vec<Line> = Vec::new();
    for dev in &problem_devices {
        lines.push(Line::from(vec![
            Span::styled(
                format!("{} ", dev.slot),
                Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
            ),
            Span::raw(format!("({}) — {}", dev.pci_id, dev.driver.as_deref().unwrap_or("no driver"))),
        ]));
        for issue in &dev.issues {
            let color = match issue.severity {
                IssueSeverity::Critical => Color::Red,
                IssueSeverity::High => Color::LightRed,
                IssueSeverity::Warning => Color::Yellow,
                IssueSeverity::Info => Color::Green,
            };
            lines.push(Line::from(vec![
                Span::raw("  "),
                Span::styled(format!("[{:?}] ", issue.severity), Style::default().fg(color)),
                Span::raw(&issue.description),
            ]));
            lines.push(Line::from(vec![
                Span::raw("    → "),
                Span::styled(&issue.remediation, Style::default().fg(Color::DarkGray)),
            ]));
        }
        lines.push(Line::raw(""));
    }

    if lines.is_empty() {
        lines.push(Line::styled("  No issues detected — system is clean.", Style::default().fg(Color::Green)));
    }

    let details = Paragraph::new(lines)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(" Issue Details "))
        .wrap(Wrap { trim: true });
    frame.render_widget(details, chunks[1]);
}

// === Screen: Status Dashboard ===

fn render_status_dashboard(frame: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(area);

    let left = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(10), Constraint::Min(5)])
        .split(chunks[0]);

    // System info
    let issue_count: usize = app.report.devices.iter()
        .map(|d| d.issues.len())
        .sum();

    let sys_info = Paragraph::new(vec![
        Line::from(vec![
            Span::styled("Kernel: ", Style::default().fg(Color::Yellow)),
            Span::raw(&app.report.kernel_version),
        ]),
        Line::from(vec![
            Span::styled("Scan Time: ", Style::default().fg(Color::Yellow)),
            Span::raw(&app.report.timestamp),
        ]),
        Line::from(vec![
            Span::styled("Devices: ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{}", app.report.devices.len())),
        ]),
        Line::from(vec![
            Span::styled("Issues: ", Style::default().fg(Color::Yellow)),
            Span::raw(format!("{}", issue_count)),
        ]),
        Line::from(vec![
            Span::styled("Risk: ", Style::default().fg(Color::Yellow)),
            Span::styled(format!("{:?}", app.report.risk_level), risk_style(&app.report.risk_level)),
        ]),
        Line::raw(""),
        Line::from(vec![
            Span::styled("IOMMU: ", Style::default().fg(Color::Yellow)),
            Span::raw(if app.report.iommu.enabled { "enabled" } else { "disabled" }),
            Span::raw(format!(" ({} groups)",  app.report.iommu.group_count)),
        ]),
    ])
    .block(Block::default()
        .borders(Borders::ALL)
        .title(" System Overview "));
    frame.render_widget(sys_info, left[0]);

    // ACPI errors
    let acpi_lines: Vec<Line> = if app.report.acpi_errors.is_empty() {
        vec![Line::styled("  No ACPI errors.", Style::default().fg(Color::Green))]
    } else {
        app.report.acpi_errors.iter().map(|err| {
            Line::from(vec![
                Span::styled(&err.method, Style::default().fg(Color::Red)),
                Span::raw(format!(": {} ({})", err.description, err.error_code)),
            ])
        }).collect()
    };

    let acpi = Paragraph::new(acpi_lines)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(format!(" ACPI Errors ({}) ", app.report.acpi_errors.len())));
    frame.render_widget(acpi, left[1]);

    // Device class breakdown (right side)
    let mut class_counts: std::collections::HashMap<&str, usize> = std::collections::HashMap::new();
    for dev in &app.report.devices {
        *class_counts.entry(&dev.class).or_insert(0) += 1;
    }
    let mut class_lines: Vec<Line> = class_counts.iter()
        .map(|(class, count)| {
            Line::from(format!("  {:3} × {}", count, class))
        })
        .collect();
    class_lines.sort_by(|a, b| b.to_string().cmp(&a.to_string()));

    let classes = Paragraph::new(class_lines)
        .block(Block::default()
            .borders(Borders::ALL)
            .title(" Device Classes "));
    frame.render_widget(classes, chunks[1]);
}

// === Helpers ===

fn format_power_state(state: &PowerState) -> String {
    match state {
        PowerState::D0 => "D0".to_string(),
        PowerState::D1 => "D1".to_string(),
        PowerState::D2 => "D2".to_string(),
        PowerState::D3Hot => "D3hot".to_string(),
        PowerState::D3Cold => "D3cold".to_string(),
        PowerState::Unknown => "?".to_string(),
    }
}

fn risk_style(risk: &RiskLevel) -> Style {
    match risk {
        RiskLevel::Clean => Style::default().fg(Color::Green),
        RiskLevel::Low => Style::default().fg(Color::Green),
        RiskLevel::Medium => Style::default().fg(Color::Yellow),
        RiskLevel::High => Style::default().fg(Color::LightRed),
        RiskLevel::Critical => Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
    }
}
