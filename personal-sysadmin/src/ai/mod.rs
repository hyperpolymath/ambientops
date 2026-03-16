// SPDX-License-Identifier: PMPL-1.0-or-later
//! AI/SLM integration - local model with Claude fallback

use anyhow::Result;
use crate::storage::Storage;
use crate::cache::Cache;

/// Diagnose a problem using AI
pub async fn diagnose(
    problem: &str,
    local_only: bool,
    _storage: &Storage,
    cache: &Cache,
) -> Result<()> {
    println!("Diagnosing: {}", problem);
    println!("{}", "-".repeat(50));

    // Step 1: Check rules first
    println!("\n[1/3] Checking rules...");
    // Would check rules engine here

    // Step 2: Search knowledge base
    println!("[2/3] Searching knowledge base...");
    let cached = cache.get_solution_lookup(&hash_problem(problem)).await?;
    if let Some(solution_id) = cached {
        println!("  Found cached solution: {}", solution_id);
        // Would retrieve and display solution
        return Ok(());
    }

    // Step 3: Query SLM
    println!("[3/3] Querying SLM...");

    if local_only {
        query_local_slm(problem).await?;
    } else {
        // Try local first, fall back to Claude
        match query_local_slm(problem).await {
            Ok(response) if !response.is_empty() => {
                println!("\nLocal SLM response:\n{}", response);
            }
            _ => {
                println!("  Local SLM unavailable, falling back to Claude...");
                query_claude(problem).await?;
            }
        }
    }

    Ok(())
}

fn hash_problem(problem: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    problem.to_lowercase().hash(&mut hasher);
    format!("{:x}", hasher.finish())
}

async fn query_local_slm(problem: &str) -> Result<String> {
    // Would use ollama-rs to query local model
    // For now, check if Ollama is running
    let check = tokio::process::Command::new("curl")
        .args(["-s", "http://localhost:11434/api/tags"])
        .output()
        .await;

    match check {
        Ok(output) if output.status.success() => {
            // Ollama is running, query it
            let response = tokio::process::Command::new("curl")
                .args([
                    "-s",
                    "-X", "POST",
                    "http://localhost:11434/api/generate",
                    "-d", &format!(
                        r#"{{"model": "llama3.2", "prompt": "You are a Linux system administrator assistant. Help with this problem: {}", "stream": false}}"#,
                        problem.replace('"', "\\\"")
                    ),
                ])
                .output()
                .await?;

            Ok(String::from_utf8_lossy(&response.stdout).to_string())
        }
        _ => {
            println!("  Ollama not running. Install with: curl -fsSL https://ollama.com/install.sh | sh");
            Ok(String::new())
        }
    }
}

async fn query_claude(problem: &str) -> Result<()> {
    // Would use Claude API
    // For now, suggest using claude CLI
    println!("\n  To query Claude directly:");
    println!("    claude \"{}\"", problem);

    Ok(())
}
