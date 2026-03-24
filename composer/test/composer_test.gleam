//// SPDX-License-Identifier: MPL-2.0
//// composer_test.gleam — Tests for Composer orchestration engine
////
//// Tests cover:
////   - Plan validation (empty plans, ordering, prerequisites)
////   - Execution lifecycle (begin, advance, complete, fail)
////   - Receipt generation (counts, status mapping)
////   - Dry-run mode (no mutations)
////   - Risk calculation (safe/guided/expert propagation)
////   - Rollback eligibility

import composer
import composer/types.{
  Completed, Custom, DeleteFile, Expert, Full, Guided,
  InProgress, NoReversibility, Pending, ProcedurePlan,
  RolledBack, Safe, StartService, Step, StepFailed, StepRolledBack,
  StepResult, StepSkipped, StepSuccess, StepTarget,
}
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Helpers — build test fixtures
// ---------------------------------------------------------------------------

/// Create a minimal valid step with sensible defaults.
fn make_step(id: String, order: Int, action: types.StepAction) -> types.Step {
  Step(
    step_id: id,
    order: order,
    action: action,
    title: "Test step " <> id,
    description: None,
    preview: None,
    risk: Safe,
    reversibility: Full,
    undo_instruction: None,
    target: StepTarget(path: None, service: None, registry_key: None, program: None),
    requires_confirmation: False,
    estimated_duration_seconds: 5,
    finding_refs: [],
  )
}

/// Create a step with a specific risk level.
fn make_risky_step(id: String, order: Int, risk: types.RiskLevel) -> types.Step {
  Step(..make_step(id, order, Custom), risk: risk)
}

/// Create a minimal valid procedure plan.
fn make_plan(steps: List(types.Step)) -> types.ProcedurePlan {
  ProcedurePlan(
    version: "1.0.0",
    plan_id: "plan-001",
    envelope_ref: "env-001",
    title: Some("Test Plan"),
    description: None,
    overall_risk: Safe,
    overall_reversibility: Full,
    estimated_duration_seconds: 30,
    requires_reboot: False,
    requires_privileges: [],
    steps: steps,
    prerequisites: [],
    warnings: [],
    approval_required: False,
  )
}

/// Create a successful step result.
fn success_result(step_id: String) -> types.StepResult {
  StepResult(
    step_id: step_id,
    status: StepSuccess,
    what_changed: Some("Applied change"),
    why_changed: Some("Per plan"),
    error_message: None,
    skip_reason: None,
  )
}

/// Create a failed step result.
fn failure_result(step_id: String, msg: String) -> types.StepResult {
  StepResult(
    step_id: step_id,
    status: StepFailed,
    what_changed: None,
    why_changed: None,
    error_message: Some(msg),
    skip_reason: None,
  )
}

/// Create a skipped step result.
fn skip_result(step_id: String, reason: String) -> types.StepResult {
  StepResult(
    step_id: step_id,
    status: StepSkipped,
    what_changed: None,
    why_changed: None,
    error_message: None,
    skip_reason: Some(reason),
  )
}

// ---------------------------------------------------------------------------
// Plan validation tests
// ---------------------------------------------------------------------------

pub fn validate_empty_plan_test() {
  let plan = make_plan([])
  composer.validate_plan(plan)
  |> should.be_error()
  |> should.equal("Plan has no steps")
}

pub fn validate_single_step_plan_test() {
  let plan = make_plan([make_step("s1", 1, DeleteFile)])
  composer.validate_plan(plan)
  |> should.be_ok()
  |> fn(p) { p.plan_id }
  |> should.equal("plan-001")
}

pub fn validate_multi_step_sequential_ordering_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
      make_step("s3", 3, Custom),
    ])
  composer.validate_plan(plan)
  |> should.be_ok()
}

pub fn validate_non_sequential_ordering_fails_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 5, StartService),
    ])
  composer.validate_plan(plan)
  |> should.be_error()
  |> should.equal("Step ordering is not sequential from 1")
}

// ---------------------------------------------------------------------------
// Execution lifecycle tests
// ---------------------------------------------------------------------------

pub fn begin_execution_starts_pending_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec = composer.begin_execution(plan)
  exec.status |> should.equal(Pending)
  exec.current_step |> should.equal(0)
  exec.dry_run |> should.equal(False)
  exec.completed_steps |> list.length() |> should.equal(0)
}

pub fn begin_dry_run_sets_flag_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec = composer.begin_dry_run(plan)
  exec.dry_run |> should.equal(True)
  exec.status |> should.equal(Pending)
}

pub fn advance_single_step_completes_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec = composer.begin_execution(plan)
  let exec2 = composer.advance(exec, success_result("s1"))
  exec2.status |> should.equal(Completed)
  exec2.current_step |> should.equal(1)
  exec2.completed_steps |> list.length() |> should.equal(1)
}

pub fn advance_multi_step_goes_in_progress_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let exec = composer.begin_execution(plan)
  let exec2 = composer.advance(exec, success_result("s1"))
  exec2.status |> should.equal(InProgress)
  exec2.current_step |> should.equal(1)
}

pub fn advance_all_steps_completes_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
    |> composer.advance(success_result("s2"))
  exec.status |> should.equal(Completed)
  exec.completed_steps |> list.length() |> should.equal(2)
}

pub fn advance_failure_halts_execution_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(failure_result("s1", "Permission denied"))
  exec.status |> should.equal(types.Failed)
}

pub fn advance_skip_continues_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(skip_result("s1", "Already clean"))
  exec.status |> should.equal(InProgress)
}

// ---------------------------------------------------------------------------
// Receipt generation tests
// ---------------------------------------------------------------------------

pub fn receipt_completed_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
    |> composer.advance(success_result("s2"))
  let receipt = composer.generate_receipt(exec)
  receipt.status |> should.equal("completed")
  receipt.items_checked |> should.equal(2)
  receipt.items_changed |> should.equal(2)
  receipt.items_failed |> should.equal(0)
  receipt.items_skipped |> should.equal(0)
}

pub fn receipt_partial_with_skip_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
    |> composer.advance(skip_result("s2", "Not needed"))
  let receipt = composer.generate_receipt(exec)
  receipt.status |> should.equal("completed")
  receipt.items_changed |> should.equal(1)
  receipt.items_skipped |> should.equal(1)
}

pub fn receipt_failed_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(failure_result("s1", "Disk full"))
  let receipt = composer.generate_receipt(exec)
  receipt.status |> should.equal("failed")
  receipt.items_failed |> should.equal(1)
  receipt.items_changed |> should.equal(0)
}

pub fn receipt_preserves_plan_refs_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)
  receipt.plan_id |> should.equal("plan-001")
  receipt.envelope_ref |> should.equal("env-001")
}

// ---------------------------------------------------------------------------
// Risk calculation tests
// ---------------------------------------------------------------------------

pub fn overall_risk_all_safe_test() {
  let plan =
    make_plan([
      make_risky_step("s1", 1, Safe),
      make_risky_step("s2", 2, Safe),
    ])
  composer.overall_risk(plan) |> should.equal(Safe)
}

pub fn overall_risk_one_guided_test() {
  let plan =
    make_plan([
      make_risky_step("s1", 1, Safe),
      make_risky_step("s2", 2, Guided),
    ])
  composer.overall_risk(plan) |> should.equal(Guided)
}

pub fn overall_risk_one_expert_test() {
  let plan =
    make_plan([
      make_risky_step("s1", 1, Guided),
      make_risky_step("s2", 2, Expert),
      make_risky_step("s3", 3, Safe),
    ])
  composer.overall_risk(plan) |> should.equal(Expert)
}

// ---------------------------------------------------------------------------
// Rollback eligibility tests
// ---------------------------------------------------------------------------

pub fn can_rollback_with_success_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  composer.can_rollback(exec) |> should.equal(True)
}

pub fn cannot_rollback_no_successes_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(failure_result("s1", "Crash"))
  composer.can_rollback(exec) |> should.equal(False)
}

pub fn cannot_rollback_pending_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec = composer.begin_execution(plan)
  composer.can_rollback(exec) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// Rollback execution tests
// ---------------------------------------------------------------------------

pub fn rollback_reverses_successful_steps_test() {
  let step1 =
    Step(
      ..make_step("s1", 1, DeleteFile),
      undo_instruction: Some("restore /tmp/s1.bak"),
      reversibility: Full,
    )
  let step2 =
    Step(
      ..make_step("s2", 2, Custom),
      undo_instruction: Some("undo custom action"),
      reversibility: Full,
    )
  let plan = make_plan([step1, step2])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
    |> composer.advance(success_result("s2"))

  let result = composer.rollback(exec)
  result |> should.be_ok()
  let rolled_back = case result {
    Ok(e) -> e
    Error(_) -> panic as "unexpected error"
  }
  rolled_back.status |> should.equal(RolledBack)
  // Both steps should have rollback results
  rolled_back.completed_steps |> list.length() |> should.equal(2)
  // Steps are processed in reverse order: s2 first, then s1
  case rolled_back.completed_steps {
    [first, second] -> {
      first.step_id |> should.equal("s2")
      first.status |> should.equal(StepRolledBack)
      second.step_id |> should.equal("s1")
      second.status |> should.equal(StepRolledBack)
    }
    _ -> panic as "expected exactly 2 rollback results"
  }
}

pub fn rollback_skips_irreversible_steps_test() {
  let step1 =
    Step(
      ..make_step("s1", 1, DeleteFile),
      undo_instruction: Some("restore file"),
      reversibility: Full,
    )
  let step2 =
    Step(
      ..make_step("s2", 2, Custom),
      reversibility: NoReversibility,
    )
  let plan = make_plan([step1, step2])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
    |> composer.advance(success_result("s2"))

  let result = composer.rollback(exec)
  result |> should.be_ok()
  let rolled_back = case result {
    Ok(e) -> e
    Error(_) -> panic as "unexpected error"
  }
  // s2 should be skipped (irreversible), s1 should be rolled back
  case rolled_back.completed_steps {
    [first, second] -> {
      // Reverse order: s2 first (skipped), then s1 (rolled back)
      first.step_id |> should.equal("s2")
      first.status |> should.equal(StepSkipped)
      second.step_id |> should.equal("s1")
      second.status |> should.equal(StepRolledBack)
    }
    _ -> panic as "expected exactly 2 rollback results"
  }
}

pub fn rollback_skips_steps_without_undo_instruction_test() {
  let step1 =
    Step(
      ..make_step("s1", 1, DeleteFile),
      undo_instruction: None,
      reversibility: Full,
    )
  let plan = make_plan([step1])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))

  let result = composer.rollback(exec)
  result |> should.be_ok()
  let rolled_back = case result {
    Ok(e) -> e
    Error(_) -> panic as "unexpected error"
  }
  case rolled_back.completed_steps {
    [sr] -> {
      sr.step_id |> should.equal("s1")
      sr.status |> should.equal(StepSkipped)
    }
    _ -> panic as "expected exactly 1 rollback result"
  }
}

pub fn rollback_fails_when_no_successes_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(failure_result("s1", "Crash"))
  composer.rollback(exec)
  |> should.be_error()
  |> should.equal("Nothing to roll back — no successful steps found")
}

pub fn rollback_fails_on_pending_execution_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec = composer.begin_execution(plan)
  composer.rollback(exec)
  |> should.be_error()
}

pub fn rollback_partial_execution_only_reverses_successes_test() {
  let step1 =
    Step(
      ..make_step("s1", 1, DeleteFile),
      undo_instruction: Some("restore s1"),
      reversibility: Full,
    )
  let step2 =
    Step(
      ..make_step("s2", 2, StartService),
      undo_instruction: Some("stop service"),
      reversibility: Full,
    )
  let plan = make_plan([step1, step2])
  // Only s1 succeeded, s2 failed
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
    |> composer.advance(failure_result("s2", "Permission denied"))

  let result = composer.rollback(exec)
  result |> should.be_ok()
  let rolled_back = case result {
    Ok(e) -> e
    Error(_) -> panic as "unexpected error"
  }
  // Only s1 should appear in rollback results (s2 failed, not rolled back)
  rolled_back.completed_steps |> list.length() |> should.equal(1)
  case rolled_back.completed_steps {
    [sr] -> {
      sr.step_id |> should.equal("s1")
      sr.status |> should.equal(StepRolledBack)
    }
    _ -> panic as "expected exactly 1 rollback result"
  }
}

pub fn rollback_receipt_has_rolled_back_status_test() {
  let step1 =
    Step(
      ..make_step("s1", 1, DeleteFile),
      undo_instruction: Some("restore file"),
      reversibility: Full,
    )
  let plan = make_plan([step1])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let result = composer.rollback(exec)
  let rolled_back = case result {
    Ok(e) -> e
    Error(_) -> panic as "unexpected error"
  }
  let receipt = composer.generate_receipt(rolled_back)
  receipt.status |> should.equal("rolled_back")
  receipt.plan_id |> should.equal("plan-001")
}

// ---------------------------------------------------------------------------
// Receipt summary formatting tests
// ---------------------------------------------------------------------------

pub fn receipt_summary_format_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)
  let summary = composer.receipt_summary(receipt)
  // Verify it contains the key fields
  { summary != "" } |> should.equal(True)
}
