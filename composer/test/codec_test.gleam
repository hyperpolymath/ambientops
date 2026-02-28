//// SPDX-License-Identifier: MPL-2.0
//// codec_test.gleam — Tests for Composer JSON codec
////
//// Tests cover:
////   - Enum string conversions (risk, reversibility, action, status, privilege)
////   - Receipt encoding to JSON
////   - ProcedurePlan round-trip (encode → decode → verify)
////   - ProcedurePlan decoding from JSON string
////   - Error handling for malformed input

import composer
import composer/codec
import composer/types.{
  Custom, DeleteFile, Expert, Full, Guided, NoReversibility, Partial,
  Prerequisite, ProcedurePlan, Safe, StartService, Step, StepResult, StepTarget,
}
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Helpers — reuse test fixtures from composer_test
// ---------------------------------------------------------------------------

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

fn success_result(step_id: String) -> types.StepResult {
  StepResult(
    step_id: step_id,
    status: types.StepSuccess,
    what_changed: Some("Applied change"),
    why_changed: Some("Per plan"),
    error_message: None,
    skip_reason: None,
  )
}

// ---------------------------------------------------------------------------
// Enum conversion tests
// ---------------------------------------------------------------------------

pub fn risk_level_round_trip_test() {
  codec.encode_risk_level(Safe)
  |> codec.decode_risk_level()
  |> should.be_ok()
  |> should.equal(Safe)

  codec.encode_risk_level(Guided)
  |> codec.decode_risk_level()
  |> should.be_ok()
  |> should.equal(Guided)

  codec.encode_risk_level(Expert)
  |> codec.decode_risk_level()
  |> should.be_ok()
  |> should.equal(Expert)
}

pub fn reversibility_round_trip_test() {
  codec.encode_reversibility(Full)
  |> codec.decode_reversibility()
  |> should.be_ok()
  |> should.equal(Full)

  codec.encode_reversibility(Partial)
  |> codec.decode_reversibility()
  |> should.be_ok()
  |> should.equal(Partial)

  codec.encode_reversibility(NoReversibility)
  |> codec.decode_reversibility()
  |> should.be_ok()
  |> should.equal(NoReversibility)
}

pub fn step_action_round_trip_test() {
  codec.encode_step_action(DeleteFile)
  |> codec.decode_step_action()
  |> should.be_ok()
  |> should.equal(DeleteFile)

  codec.encode_step_action(StartService)
  |> codec.decode_step_action()
  |> should.be_ok()
  |> should.equal(StartService)

  codec.encode_step_action(Custom)
  |> codec.decode_step_action()
  |> should.be_ok()
  |> should.equal(Custom)
}

pub fn unknown_risk_level_errors_test() {
  codec.decode_risk_level("unknown")
  |> should.be_error()
}

pub fn unknown_action_errors_test() {
  codec.decode_step_action("fly_to_moon")
  |> should.be_error()
}

pub fn privilege_round_trip_test() {
  codec.encode_privilege(types.Root)
  |> codec.decode_privilege()
  |> should.be_ok()
  |> should.equal(types.Root)
}

// ---------------------------------------------------------------------------
// Receipt encoding tests
// ---------------------------------------------------------------------------

pub fn encode_receipt_produces_valid_json_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)
  let json_str = codec.receipt_to_json(receipt)

  // Verify it's valid JSON by decoding it
  json.decode(json_str, fn(d) { Ok(d) })
  |> should.be_ok()
}

pub fn encode_receipt_contains_plan_id_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)
  let json_str = codec.receipt_to_json(receipt)

  string.contains(json_str, "plan-001")
  |> should.equal(True)
}

pub fn encode_receipt_contains_status_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)
  let json_str = codec.receipt_to_json(receipt)

  string.contains(json_str, "\"completed\"")
  |> should.equal(True)
}

pub fn encode_receipt_contains_step_results_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)
  let json_str = codec.receipt_to_json(receipt)

  string.contains(json_str, "step_results")
  |> should.equal(True)
  string.contains(json_str, "\"success\"")
  |> should.equal(True)
}

pub fn encode_receipt_counts_correct_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)
  let json_str = codec.receipt_to_json(receipt)

  string.contains(json_str, "\"items_checked\":1")
  |> should.equal(True)
  string.contains(json_str, "\"items_changed\":1")
  |> should.equal(True)
}

// ---------------------------------------------------------------------------
// ProcedurePlan encoding tests
// ---------------------------------------------------------------------------

pub fn encode_plan_produces_valid_json_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let json_str = codec.plan_to_json(plan)

  json.decode(json_str, fn(d) { Ok(d) })
  |> should.be_ok()
}

pub fn encode_plan_contains_all_fields_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let json_str = codec.plan_to_json(plan)

  string.contains(json_str, "\"version\"")
  |> should.equal(True)
  string.contains(json_str, "\"plan_id\"")
  |> should.equal(True)
  string.contains(json_str, "\"envelope_ref\"")
  |> should.equal(True)
  string.contains(json_str, "\"steps\"")
  |> should.equal(True)
  string.contains(json_str, "\"overall_risk\"")
  |> should.equal(True)
}

// ---------------------------------------------------------------------------
// ProcedurePlan round-trip tests (encode → decode → verify)
// ---------------------------------------------------------------------------

pub fn plan_round_trip_preserves_identity_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let json_str = codec.plan_to_json(plan)
  let decoded = codec.plan_from_json(json_str)

  decoded |> should.be_ok()
  let p = case decoded {
    Ok(p) -> p
    Error(_) -> plan
  }
  p.plan_id |> should.equal("plan-001")
  p.version |> should.equal("1.0.0")
  p.envelope_ref |> should.equal("env-001")
}

pub fn plan_round_trip_preserves_steps_test() {
  let plan =
    make_plan([
      make_step("s1", 1, DeleteFile),
      make_step("s2", 2, StartService),
    ])
  let json_str = codec.plan_to_json(plan)
  let decoded = codec.plan_from_json(json_str)

  let p = case decoded {
    Ok(p) -> p
    Error(_) -> plan
  }

  case p.steps {
    [s1, s2] -> {
      s1.step_id |> should.equal("s1")
      s1.order |> should.equal(1)
      s2.step_id |> should.equal("s2")
      s2.order |> should.equal(2)
    }
    _ -> should.fail()
  }
}

pub fn plan_round_trip_preserves_risk_test() {
  let plan = ProcedurePlan(
    ..make_plan([make_step("s1", 1, Custom)]),
    overall_risk: Expert,
    overall_reversibility: Partial,
  )
  let json_str = codec.plan_to_json(plan)
  let decoded = codec.plan_from_json(json_str)

  let p = case decoded {
    Ok(p) -> p
    Error(_) -> plan
  }
  p.overall_risk |> should.equal(Expert)
  p.overall_reversibility |> should.equal(Partial)
}

pub fn plan_round_trip_preserves_optional_fields_test() {
  let plan = ProcedurePlan(
    ..make_plan([make_step("s1", 1, Custom)]),
    title: Some("My Important Plan"),
    description: Some("Does important things"),
    requires_reboot: True,
    approval_required: True,
    warnings: ["Be careful", "Backup first"],
  )
  let json_str = codec.plan_to_json(plan)
  let decoded = codec.plan_from_json(json_str)

  let p = case decoded {
    Ok(p) -> p
    Error(_) -> plan
  }
  p.title |> should.equal(Some("My Important Plan"))
  p.description |> should.equal(Some("Does important things"))
  p.requires_reboot |> should.equal(True)
  p.approval_required |> should.equal(True)
}

pub fn plan_round_trip_preserves_prerequisites_test() {
  let plan = ProcedurePlan(
    ..make_plan([make_step("s1", 1, Custom)]),
    prerequisites: [
      Prerequisite(
        check: "disk_space > 1GB",
        description: "Need at least 1GB free",
        blocking: True,
      ),
    ],
  )
  let json_str = codec.plan_to_json(plan)
  let decoded = codec.plan_from_json(json_str)

  let p = case decoded {
    Ok(p) -> p
    Error(_) -> plan
  }
  case p.prerequisites {
    [prereq] -> {
      prereq.check |> should.equal("disk_space > 1GB")
      prereq.blocking |> should.equal(True)
    }
    _ -> should.fail()
  }
}

pub fn plan_round_trip_preserves_step_target_test() {
  let step = Step(
    ..make_step("s1", 1, DeleteFile),
    target: StepTarget(
      path: Some("/tmp/old-cache"),
      service: None,
      registry_key: None,
      program: None,
    ),
  )
  let plan = make_plan([step])
  let json_str = codec.plan_to_json(plan)
  let decoded = codec.plan_from_json(json_str)

  let p = case decoded {
    Ok(p) -> p
    Error(_) -> plan
  }
  case p.steps {
    [s1] -> s1.target.path |> should.equal(Some("/tmp/old-cache"))
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Decode error handling tests
// ---------------------------------------------------------------------------

pub fn decode_invalid_json_errors_test() {
  codec.plan_from_json("not valid json{{{")
  |> should.be_error()
  |> should.equal("Invalid JSON")
}

pub fn decode_missing_required_field_errors_test() {
  // Missing plan_id
  codec.plan_from_json("{\"version\":\"1.0.0\",\"envelope_ref\":\"e1\"}")
  |> should.be_error()
}

pub fn decode_empty_object_errors_test() {
  codec.plan_from_json("{}")
  |> should.be_error()
}

// ---------------------------------------------------------------------------
// Receipt round-trip validation test
// ---------------------------------------------------------------------------

pub fn receipt_round_trip_validates_test() {
  let plan = make_plan([make_step("s1", 1, Custom)])
  let exec =
    composer.begin_execution(plan)
    |> composer.advance(success_result("s1"))
  let receipt = composer.generate_receipt(exec)

  codec.receipt_round_trip(receipt)
  |> should.equal(True)
}
