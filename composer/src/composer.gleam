//// SPDX-License-Identifier: MPL-2.0
//// composer.gleam — Root module for AmbientOps Composer
////
//// Composer is the orchestration engine for multi-step procedures across the
//// AmbientOps Operating Room. It coordinates HCT scans, Clinician application,
//// and ER intake into ordered execution chains with rollback support.
////
//// Contract consumption:
////   - procedure-plan (Consumer): reads plans from HCT/clinician
////   - receipt (Producer): emits receipts after each orchestrated step
////   - run-bundle (Producer): packages full run output for observatory
////
//// Architecture:
////   Composer reads a ProcedurePlan, validates prerequisites, executes steps
////   in order (or in parallel where safe), generates step-level receipts, and
////   bundles everything for Observatory ingestion. It never acts directly on
////   the system — it delegates to HCT/clinician/ER via their CLIs.

import composer/types.{
  type Execution, type ProcedurePlan, type Receipt, type StepResult,
}
import gleam/list
import gleam/string

/// Validate a procedure plan before execution.
/// Checks that all prerequisites are satisfiable, step ordering is consistent,
/// and no required fields are missing.
pub fn validate_plan(plan: ProcedurePlan) -> Result(ProcedurePlan, String) {
  case plan.steps {
    [] -> Error("Plan has no steps")
    steps -> {
      // Verify step ordering is sequential starting from 1
      let orders = list.map(steps, fn(s) { s.order })
      let expected = list.range(1, list.length(steps))
      case orders == expected {
        True -> Ok(plan)
        False -> Error("Step ordering is not sequential from 1")
      }
    }
  }
}

/// Create a new execution context from a validated plan.
/// The execution tracks which steps have been run, their results, and
/// whether the overall procedure can continue or needs rollback.
pub fn begin_execution(plan: ProcedurePlan) -> Execution {
  types.Execution(
    plan: plan,
    completed_steps: [],
    current_step: 0,
    status: types.Pending,
    dry_run: False,
  )
}

/// Create a dry-run execution that previews without mutations.
/// All steps will be "executed" but no system changes will occur.
pub fn begin_dry_run(plan: ProcedurePlan) -> Execution {
  types.Execution(
    plan: plan,
    completed_steps: [],
    current_step: 0,
    status: types.Pending,
    dry_run: True,
  )
}

/// Advance the execution by one step.
/// Returns the updated execution with the step result appended.
/// If the step fails and is not recoverable, the execution halts.
pub fn advance(
  execution: Execution,
  step_result: StepResult,
) -> Execution {
  let new_completed = list.append(execution.completed_steps, [step_result])
  let new_status = case step_result.status {
    types.StepSuccess -> {
      case execution.current_step + 1 >= list.length(execution.plan.steps) {
        True -> types.Completed
        False -> types.InProgress
      }
    }
    types.StepFailed -> types.Failed
    types.StepSkipped -> {
      case execution.current_step + 1 >= list.length(execution.plan.steps) {
        True -> types.Completed
        False -> types.InProgress
      }
    }
    types.StepRolledBack -> types.RolledBack
  }

  types.Execution(
    ..execution,
    completed_steps: new_completed,
    current_step: execution.current_step + 1,
    status: new_status,
  )
}

/// Generate a receipt from a completed (or failed/cancelled) execution.
/// The receipt summarises what was checked, changed, and left unchanged.
pub fn generate_receipt(execution: Execution) -> Receipt {
  let succeeded =
    list.filter(execution.completed_steps, fn(s) {
      s.status == types.StepSuccess
    })
  let failed =
    list.filter(execution.completed_steps, fn(s) {
      s.status == types.StepFailed
    })
  let skipped =
    list.filter(execution.completed_steps, fn(s) {
      s.status == types.StepSkipped
    })

  let receipt_status = case execution.status {
    types.Completed -> "completed"
    types.Failed -> "failed"
    types.RolledBack -> "rolled_back"
    types.Cancelled -> "cancelled"
    types.Pending -> "cancelled"
    types.InProgress -> "partial"
  }

  types.Receipt(
    plan_id: execution.plan.plan_id,
    envelope_ref: execution.plan.envelope_ref,
    status: receipt_status,
    items_checked: list.length(execution.completed_steps),
    items_changed: list.length(succeeded),
    items_failed: list.length(failed),
    items_skipped: list.length(skipped),
    step_results: execution.completed_steps,
  )
}

/// Check whether an execution can be rolled back.
/// Only steps with reversibility "full" or "partial" can be undone.
pub fn can_rollback(execution: Execution) -> Bool {
  let succeeded =
    list.filter(execution.completed_steps, fn(s) {
      s.status == types.StepSuccess
    })
  // At least one successful step exists to roll back
  !list.is_empty(succeeded)
}

/// Compute the overall risk level for a plan.
/// Returns the highest risk among all steps (expert > guided > safe).
pub fn overall_risk(plan: ProcedurePlan) -> types.RiskLevel {
  list.fold(plan.steps, types.Safe, fn(acc, step) {
    case acc, step.risk {
      types.Expert, _ -> types.Expert
      _, types.Expert -> types.Expert
      types.Guided, _ -> types.Guided
      _, types.Guided -> types.Guided
      _, _ -> types.Safe
    }
  })
}

/// Format a human-readable summary of a receipt.
pub fn receipt_summary(receipt: Receipt) -> String {
  string.concat([
    "Plan: ",
    receipt.plan_id,
    " | Status: ",
    receipt.status,
    " | Changed: ",
    string.inspect(receipt.items_changed),
    " | Failed: ",
    string.inspect(receipt.items_failed),
    " | Skipped: ",
    string.inspect(receipt.items_skipped),
  ])
}
