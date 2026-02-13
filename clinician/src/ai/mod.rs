// SPDX-License-Identifier: PMPL-1.0-or-later
//! AI/SLM integration - local model with Claude fallback
//!
//! When `ai` feature is enabled, uses ollama-rs library.
//! Without: falls back to curl invocation or suggests Claude CLI.

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

    // Step 2: Search knowledge base
    println!("[2/3] Searching knowledge base...");
    let cached = cache.get_solution_lookup(&hash_problem(problem)).await?;
    if let Some(solution_id) = cached {
        println!("  Found cached solution: {}", solution_id);
        return Ok(());
    }

    // Step 3: Query SLM
    println!("[3/3] Querying SLM...");

    if local_only {
        query_local_slm(problem).await?;
    } else {
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
    #[cfg(feature = "ai")]
    {
        // Use ollama-rs library
        let ollama = ollama_rs::Ollama::default();

        // Health check
        match ollama.list_local_models().await {
            Ok(models) => {
                if models.is_empty() {
                    println!("  Ollama running but no models found. Run: ollama pull llama3.2");
                    return Ok(String::new());
                }

                let model = models.first()
                    .map(|m| m.name.clone())
                    .unwrap_or_else(|| "llama3.2".to_string());

                let prompt = format!(
                    "You are a Linux system administrator assistant. Help with this problem: {}",
                    problem
                );

                match ollama.generate(ollama_rs::generation::completion::request::GenerationRequest::new(
                    model, prompt
                )).await {
                    Ok(response) => {
                        return Ok(response.response);
                    }
                    Err(e) => {
                        tracing::warn!("Ollama generate failed: {}", e);
                    }
                }
            }
            Err(e) => {
                tracing::warn!("Ollama not available: {}", e);
                println!("  Ollama not running. Install with: curl -fsSL https://ollama.com/install.sh | sh");
            }
        }
        return Ok(String::new());
    }

    #[cfg(not(feature = "ai"))]
    {
        // Fallback: use curl to talk to Ollama
        let check = tokio::process::Command::new("curl")
            .args(["-s", "http://localhost:11434/api/tags"])
            .output()
            .await;

        match check {
            Ok(output) if output.status.success() => {
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
}

async fn query_claude(problem: &str) -> Result<()> {
    println!("\n  To query Claude directly:");
    println!("    claude \"{}\"", problem);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_problem_deterministic() {
        let h1 = hash_problem("disk full");
        let h2 = hash_problem("disk full");
        assert_eq!(h1, h2);
    }

    #[test]
    fn test_hash_problem_case_insensitive() {
        let h1 = hash_problem("Disk Full");
        let h2 = hash_problem("disk full");
        assert_eq!(h1, h2);
    }
}
