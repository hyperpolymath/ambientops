// SPDX-License-Identifier: PMPL-1.0-or-later
//! echidna integration — formal verification of procedure reversibility
//!
//! Invokes echidna to verify that remediation procedures are safely reversible.

use anyhow::Result;
use super::VerificationResult;

/// Verify that a procedure file is safely reversible
pub async fn verify(procedure_path: &str) -> Result<()> {
    println!("Verifying procedure reversibility: {}", procedure_path);
    println!("{}", "-".repeat(50));

    // Check if echidna is available
    let which = tokio::process::Command::new("which")
        .arg("echidna")
        .output()
        .await;

    match which {
        Ok(w) if w.status.success() => {
            let result = tokio::process::Command::new("echidna")
                .args(["verify", "--reversibility", procedure_path])
                .output()
                .await?;

            if result.status.success() {
                let stdout = String::from_utf8_lossy(&result.stdout);
                let verification = parse_verification_output(&stdout, procedure_path);
                print_verification(&verification);
            } else {
                let stderr = String::from_utf8_lossy(&result.stderr);
                println!("  Verification failed: {}", stderr);
            }
        }
        _ => {
            println!("  echidna not found in PATH.");
            println!("  Expected at: ~/Documents/hyperpolymath-repos/echidna");
            println!("  Build: cd ~/Documents/hyperpolymath-repos/echidna && cargo build --release");
            println!("\n  Manual check: verify each apply step has a matching undo step.");
        }
    }

    Ok(())
}

fn parse_verification_output(output: &str, procedure_path: &str) -> VerificationResult {
    let reversible = output.contains("REVERSIBLE: true") || output.contains("reversible: yes");
    let proof_status = if output.contains("PROVEN") {
        "proven".to_string()
    } else if output.contains("ADMITTED") {
        "admitted".to_string()
    } else {
        "unknown".to_string()
    };

    let details: Vec<String> = output
        .lines()
        .filter(|line| line.starts_with("  -") || line.starts_with("  *"))
        .map(|line| line.trim().to_string())
        .collect();

    VerificationResult {
        procedure: procedure_path.to_string(),
        reversible,
        proof_status,
        details,
    }
}

fn print_verification(result: &VerificationResult) {
    println!("\n  Procedure: {}", result.procedure);
    println!(
        "  Reversible: {}",
        if result.reversible { "YES" } else { "NO" }
    );
    println!("  Proof Status: {}", result.proof_status);

    if !result.details.is_empty() {
        println!("\n  Details:");
        for detail in &result.details {
            println!("    {}", detail);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_verification_proven_reversible() {
        let output = "Checking procedure...\nREVERSIBLE: true\nPROVEN\n  - Step 1 invertible\n  - Step 2 invertible";
        let result = parse_verification_output(output, "test.json");
        assert!(result.reversible);
        assert_eq!(result.proof_status, "proven");
        assert_eq!(result.details.len(), 2);
    }

    #[test]
    fn test_parse_verification_not_reversible() {
        let output = "Checking procedure...\nREVERSIBLE: false\nADMITTED\n  - Step 3 not invertible";
        let result = parse_verification_output(output, "test.json");
        assert!(!result.reversible);
        assert_eq!(result.proof_status, "admitted");
    }

    #[test]
    fn test_parse_verification_empty() {
        let output = "No output";
        let result = parse_verification_output(output, "test.json");
        assert!(!result.reversible);
        assert_eq!(result.proof_status, "unknown");
        assert!(result.details.is_empty());
    }
}
