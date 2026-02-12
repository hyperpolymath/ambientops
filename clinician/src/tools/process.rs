// SPDX-License-Identifier: PMPL-1.0-or-later
//! Process management tools (like Process Explorer)

use anyhow::Result;
use sysinfo::{System, Pid};
use crate::storage::Storage;
use crate::cache::Cache;

/// Process action types
#[derive(Debug, Clone)]
pub enum ProcessAction {
    List { sort: String, top: Option<usize> },
    Tree,
    Find { pattern: String },
    Info { pid: u32 },
    Kill { pid: u32 },
    Watch { pid: u32 },
}

/// Handle process subcommands
pub async fn handle(action: ProcessAction, _storage: &Storage, _cache: &Cache) -> Result<()> {
    let mut sys = System::new_all();
    sys.refresh_all();

    match action {
        ProcessAction::List { sort, top } => {
            list_processes(&sys, &sort, top)?;
        }
        ProcessAction::Tree => {
            show_process_tree(&sys)?;
        }
        ProcessAction::Find { pattern } => {
            find_processes(&sys, &pattern)?;
        }
        ProcessAction::Info { pid } => {
            show_process_info(&sys, pid)?;
        }
        ProcessAction::Kill { pid } => {
            kill_process(&sys, pid)?;
        }
        ProcessAction::Watch { pid } => {
            watch_process(pid).await?;
        }
    }

    Ok(())
}

fn list_processes(sys: &System, sort_by: &str, top: Option<usize>) -> Result<()> {
    let mut processes: Vec<_> = sys.processes().iter().collect();

    // Sort processes
    match sort_by {
        "cpu" => processes.sort_by(|a, b| {
            b.1.cpu_usage().partial_cmp(&a.1.cpu_usage()).unwrap_or(std::cmp::Ordering::Equal)
        }),
        "mem" => processes.sort_by(|a, b| b.1.memory().cmp(&a.1.memory())),
        "pid" => processes.sort_by(|a, b| a.0.as_u32().cmp(&b.0.as_u32())),
        "name" => processes.sort_by(|a, b| a.1.name().cmp(b.1.name())),
        _ => {}
    }

    // Limit if top is specified
    let processes: Vec<_> = match top {
        Some(n) => processes.into_iter().take(n).collect(),
        None => processes,
    };

    println!("{:>7} {:>6} {:>8} {:>10} NAME", "PID", "CPU%", "MEM(MB)", "STATE");
    println!("{}", "-".repeat(60));

    for (pid, process) in processes {
        println!(
            "{:>7} {:>5.1}% {:>8.1} {:>10} {:?}",
            pid.as_u32(),
            process.cpu_usage(),
            process.memory() as f64 / 1024.0 / 1024.0,
            format!("{:?}", process.status()),
            process.name()
        );
    }

    Ok(())
}

fn show_process_tree(sys: &System) -> Result<()> {
    use std::collections::HashMap;

    // Build parent-child map
    let mut children: HashMap<u32, Vec<u32>> = HashMap::new();
    let mut roots = vec![];

    for (pid, process) in sys.processes() {
        let pid = pid.as_u32();
        if let Some(parent_pid) = process.parent() {
            children.entry(parent_pid.as_u32()).or_default().push(pid);
        } else {
            roots.push(pid);
        }
    }

    // Print tree recursively
    fn print_tree(
        sys: &System,
        pid: u32,
        children: &HashMap<u32, Vec<u32>>,
        prefix: &str,
        is_last: bool,
    ) {
        let connector = if is_last { "└── " } else { "├── " };
        let name = sys
            .process(Pid::from_u32(pid))
            .map(|p| format!("{:?}", p.name()))
            .unwrap_or_else(|| "???".to_string());

        println!("{}{}{} ({})", prefix, connector, name, pid);

        if let Some(child_pids) = children.get(&pid) {
            let new_prefix = format!("{}{}   ", prefix, if is_last { " " } else { "│" });
            for (i, &child_pid) in child_pids.iter().enumerate() {
                print_tree(sys, child_pid, children, &new_prefix, i == child_pids.len() - 1);
            }
        }
    }

    for (i, &root_pid) in roots.iter().enumerate() {
        print_tree(sys, root_pid, &children, "", i == roots.len() - 1);
    }

    Ok(())
}

fn find_processes(sys: &System, pattern: &str) -> Result<()> {
    let pattern_lower = pattern.to_lowercase();

    println!("{:>7} {:>6} {:>8} NAME", "PID", "CPU%", "MEM(MB)");
    println!("{}", "-".repeat(50));

    for (pid, process) in sys.processes() {
        let name = process.name().to_string_lossy().to_lowercase();
        let cmd_match = process.cmd().iter().any(|c| {
            c.to_string_lossy().to_lowercase().contains(&pattern_lower)
        });

        if name.contains(&pattern_lower) || cmd_match {
            println!(
                "{:>7} {:>5.1}% {:>8.1} {:?}",
                pid.as_u32(),
                process.cpu_usage(),
                process.memory() as f64 / 1024.0 / 1024.0,
                process.name()
            );
        }
    }

    Ok(())
}

fn show_process_info(sys: &System, pid: u32) -> Result<()> {
    let pid = Pid::from_u32(pid);

    if let Some(process) = sys.process(pid) {
        println!("Process Information");
        println!("{}", "=".repeat(40));
        println!("PID:        {}", pid.as_u32());
        println!("Name:       {:?}", process.name());
        println!("Status:     {:?}", process.status());
        println!("CPU Usage:  {:.1}%", process.cpu_usage());
        println!("Memory:     {:.1} MB", process.memory() as f64 / 1024.0 / 1024.0);
        println!("Virtual:    {:.1} MB", process.virtual_memory() as f64 / 1024.0 / 1024.0);

        if let Some(parent) = process.parent() {
            println!("Parent PID: {}", parent.as_u32());
        }

        println!("Start Time: {}", process.start_time());
        println!("Run Time:   {} seconds", process.run_time());

        if let Some(cwd) = process.cwd() {
            println!("CWD:        {}", cwd.display());
        }

        if let Some(exe) = process.exe() {
            println!("Executable: {}", exe.display());
        }

        println!("\nCommand Line:");
        for arg in process.cmd() {
            println!("  {:?}", arg);
        }

        println!("\nEnvironment (sample):");
        for env in process.environ().iter().take(10) {
            println!("  {:?}", env);
        }
    } else {
        println!("Process {} not found", pid.as_u32());
    }

    Ok(())
}

fn kill_process(sys: &System, pid: u32) -> Result<()> {
    let pid = Pid::from_u32(pid);

    if let Some(process) = sys.process(pid) {
        println!("Killing process {} ({:?})", pid.as_u32(), process.name());
        if process.kill() {
            println!("Process terminated successfully");
        } else {
            println!("Failed to terminate process (may need elevated permissions)");
        }
    } else {
        println!("Process {} not found", pid.as_u32());
    }

    Ok(())
}

async fn watch_process(pid: u32) -> Result<()> {
    println!("Watching process {} for anomalies...", pid);
    println!("(Press Ctrl+C to stop)");
    println!();

    let sysinfo_pid = Pid::from_u32(pid);
    let mut sys = System::new_all();

    loop {
        sys.refresh_all();

        if let Some(process) = sys.process(sysinfo_pid) {
            println!(
                "[{}] CPU: {:>5.1}%  MEM: {:>8.1} MB  Status: {:?}",
                chrono::Local::now().format("%H:%M:%S"),
                process.cpu_usage(),
                process.memory() as f64 / 1024.0 / 1024.0,
                process.status()
            );
        } else {
            println!("Process {} no longer exists", pid);
            break;
        }

        tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
    }

    Ok(())
}
