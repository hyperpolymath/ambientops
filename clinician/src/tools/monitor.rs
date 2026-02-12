// SPDX-License-Identifier: PMPL-1.0-or-later
//! Interactive monitoring dashboard

use anyhow::Result;
use sysinfo::System;
use crate::storage::Storage;
use crate::cache::Cache;

pub async fn run(_storage: &Storage, _cache: &Cache) -> Result<()> {
    println!("Interactive Monitor");
    println!("{}", "=".repeat(50));
    println!("Press Ctrl+C to exit\n");

    loop {
        let mut sys = System::new_all();
        sys.refresh_all();

        // Clear screen
        print!("\x1B[2J\x1B[1;1H");

        println!("PSA Monitor - {}", chrono::Local::now().format("%H:%M:%S"));
        println!("{}", "-".repeat(50));

        // CPU
        println!("\nCPU: {:.1}%", sys.global_cpu_usage());

        // Memory
        let mem_used = sys.used_memory();
        let mem_total = sys.total_memory();
        let mem_pct = if mem_total > 0 { (mem_used as f64 / mem_total as f64) * 100.0 } else { 0.0 };
        println!(
            "Memory: {:.1}% ({:.1} GB / {:.1} GB)",
            mem_pct,
            mem_used as f64 / 1024.0 / 1024.0 / 1024.0,
            mem_total as f64 / 1024.0 / 1024.0 / 1024.0
        );

        // Load average
        let load = System::load_average();
        println!("Load: {:.2} {:.2} {:.2}", load.one, load.five, load.fifteen);

        // Top processes
        println!("\nTop Processes (by CPU):");
        let mut procs: Vec<_> = sys.processes().iter().collect();
        procs.sort_by(|a, b| {
            b.1.cpu_usage()
                .partial_cmp(&a.1.cpu_usage())
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        for (pid, process) in procs.iter().take(5) {
            println!(
                "  {:>7} {:>5.1}% {:>8.1}MB  {:?}",
                pid.as_u32(),
                process.cpu_usage(),
                process.memory() as f64 / 1024.0 / 1024.0,
                process.name()
            );
        }

        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
    }
}
