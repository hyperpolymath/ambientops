// SPDX-License-Identifier: PMPL-1.0-or-later
//! Deployment executor

use crate::{Mustfile, MustfileError, Platform, Result, Task};
use std::collections::HashSet;
use std::process::Command;

pub struct DeploymentExecutor {
    platform: Platform,
}

impl DeploymentExecutor {
    pub fn new(platform: Platform) -> Self {
        Self { platform }
    }

    /// Deploy a complete Mustfile
    pub async fn deploy(&self, mustfile: &Mustfile) -> Result<()> {
        println!("Deploying {} v{}", mustfile.project.name, mustfile.project.version);
        println!("Platform: {} ({})", self.platform.os, self.platform.arch);
        println!("Package Manager: {}", self.platform.package_manager());
        println!();

        // Validate global requirements
        mustfile.validate_requirements()?;

        // Execute tasks in dependency order
        let task_order = self.resolve_dependencies(&mustfile)?;

        for task_name in task_order {
            if let Some(task) = mustfile.tasks.get(&task_name) {
                self.execute_task(&task_name, task)?;
            }
        }

        println!("\n✅ Deployment complete!");
        Ok(())
    }

    /// Resolve task dependencies using topological sort
    fn resolve_dependencies(&self, mustfile: &Mustfile) -> Result<Vec<String>> {
        let mut visited = HashSet::new();
        let mut stack = Vec::new();

        for task_name in mustfile.tasks.keys() {
            if !visited.contains(task_name) {
                self.visit_task(task_name, mustfile, &mut visited, &mut stack)?;
            }
        }

        stack.reverse();
        Ok(stack)
    }

    /// Visit a task and its dependencies (DFS)
    fn visit_task(
        &self,
        task_name: &str,
        mustfile: &Mustfile,
        visited: &mut HashSet<String>,
        stack: &mut Vec<String>,
    ) -> Result<()> {
        if visited.contains(task_name) {
            return Ok(());
        }

        visited.insert(task_name.to_string());

        if let Some(task) = mustfile.tasks.get(task_name) {
            // Visit dependencies first
            for dep in &task.depends_on {
                if !mustfile.tasks.contains_key(dep) {
                    return Err(MustfileError::DeploymentError(
                        format!("Task '{}' depends on unknown task '{}'", task_name, dep)
                    ));
                }
                self.visit_task(dep, mustfile, visited, stack)?;
            }
        }

        stack.push(task_name.to_string());
        Ok(())
    }

    /// Execute a single task
    fn execute_task(&self, name: &str, task: &Task) -> Result<()> {
        println!("→ Running task: {}", name);
        if let Some(desc) = &task.description {
            println!("  {}", desc);
        }

        // Check task requirements
        for file in &task.requirements.must_have {
            if !std::path::Path::new(file).exists() {
                return Err(MustfileError::RequirementError(
                    format!("Task '{}' requires missing file: {}", name, file)
                ));
            }
        }

        // Execute commands
        for (i, cmd) in task.run.iter().enumerate() {
            println!("  [{}] {}", i + 1, cmd);
            self.execute_command(cmd)?;
        }

        println!("  ✓ Task '{}' complete", name);
        Ok(())
    }

    /// Execute a shell command
    fn execute_command(&self, cmd: &str) -> Result<()> {
        let status = Command::new("sh")
            .arg("-c")
            .arg(cmd)
            .status()
            .map_err(|e| MustfileError::DeploymentError(
                format!("Failed to execute command: {}", e)
            ))?;

        if !status.success() {
            return Err(MustfileError::DeploymentError(
                format!("Command failed with exit code: {:?}", status.code())
            ));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ProjectMetadata, Requirements, TargetType};
    use std::collections::HashMap;

    #[test]
    fn test_resolve_dependencies() {
        let platform = Platform {
            os: "linux".to_string(),
            arch: "x86_64".to_string(),
            target_type: TargetType::StandardPc,
            is_immutable: false,
            deployment_priority: "nala".to_string(),
        };

        let executor = DeploymentExecutor::new(platform);

        let mut tasks = HashMap::new();
        tasks.insert("a".to_string(), Task {
            description: None,
            run: vec!["echo a".to_string()],
            requirements: Requirements::default(),
            depends_on: vec!["b".to_string()],
        });
        tasks.insert("b".to_string(), Task {
            description: None,
            run: vec!["echo b".to_string()],
            requirements: Requirements::default(),
            depends_on: vec![],
        });

        let mustfile = Mustfile {
            project: ProjectMetadata {
                name: "test".to_string(),
                version: "1.0.0".to_string(),
                description: None,
            },
            tasks,
            requirements: Requirements::default(),
            variables: HashMap::new(),
        };

        let order = executor.resolve_dependencies(&mustfile).unwrap();
        // b must come before a
        assert_eq!(order, vec!["b".to_string(), "a".to_string()]);
    }
}
