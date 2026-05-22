//// SPDX-License-Identifier: MPL-2.0
//// (MPL-2.0 preferred; MPL-2.0 required for Gleam ecosystem SPDX)
////
//// codec.gleam — JSON encoding/decoding for Composer contract types
////
//// Composer consumes ProcedurePlan (decoder) and produces Receipt (encoder).
//// All serialization follows the JSON Schema contracts in contracts/schemas/.
////
//// Encoding: Receipt, StepResult → JSON string
//// Decoding: JSON string → ProcedurePlan, Step, StepTarget, Prerequisite

import composer/types
import gleam/dynamic
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// ---------------------------------------------------------------------------
// String ↔ enum conversions
// ---------------------------------------------------------------------------

/// Encode a RiskLevel to its JSON string representation.
pub fn encode_risk_level(risk: types.RiskLevel) -> String {
  case risk {
    types.Safe -> "safe"
    types.Guided -> "guided"
    types.Expert -> "expert"
  }
}

/// Decode a JSON string to a RiskLevel.
pub fn decode_risk_level(s: String) -> Result(types.RiskLevel, String) {
  case string.lowercase(s) {
    "safe" -> Ok(types.Safe)
    "guided" -> Ok(types.Guided)
    "expert" -> Ok(types.Expert)
    _ -> Error("Unknown risk level: " <> s)
  }
}

/// Encode a Reversibility to its JSON string representation.
pub fn encode_reversibility(rev: types.Reversibility) -> String {
  case rev {
    types.Full -> "full"
    types.Partial -> "partial"
    types.NoReversibility -> "none"
  }
}

/// Decode a JSON string to a Reversibility.
pub fn decode_reversibility(s: String) -> Result(types.Reversibility, String) {
  case string.lowercase(s) {
    "full" -> Ok(types.Full)
    "partial" -> Ok(types.Partial)
    "none" -> Ok(types.NoReversibility)
    _ -> Error("Unknown reversibility: " <> s)
  }
}

/// Encode a StepAction to its JSON string representation.
pub fn encode_step_action(action: types.StepAction) -> String {
  case action {
    types.DeleteFile -> "delete_file"
    types.DeleteDirectory -> "delete_directory"
    types.MoveFile -> "move_file"
    types.CopyFile -> "copy_file"
    types.ModifyRegistry -> "modify_registry"
    types.StopService -> "stop_service"
    types.StartService -> "start_service"
    types.RestartService -> "restart_service"
    types.DisableService -> "disable_service"
    types.EnableService -> "enable_service"
    types.UninstallProgram -> "uninstall_program"
    types.RunCommand -> "run_command"
    types.ClearCache -> "clear_cache"
    types.ClearTemp -> "clear_temp"
    types.Defragment -> "defragment"
    types.UpdateDriver -> "update_driver"
    types.RepairPermissions -> "repair_permissions"
    types.Custom -> "custom"
  }
}

/// Decode a JSON string to a StepAction.
pub fn decode_step_action(s: String) -> Result(types.StepAction, String) {
  case string.lowercase(s) {
    "delete_file" -> Ok(types.DeleteFile)
    "delete_directory" -> Ok(types.DeleteDirectory)
    "move_file" -> Ok(types.MoveFile)
    "copy_file" -> Ok(types.CopyFile)
    "modify_registry" -> Ok(types.ModifyRegistry)
    "stop_service" -> Ok(types.StopService)
    "start_service" -> Ok(types.StartService)
    "restart_service" -> Ok(types.RestartService)
    "disable_service" -> Ok(types.DisableService)
    "enable_service" -> Ok(types.EnableService)
    "uninstall_program" -> Ok(types.UninstallProgram)
    "run_command" -> Ok(types.RunCommand)
    "clear_cache" -> Ok(types.ClearCache)
    "clear_temp" -> Ok(types.ClearTemp)
    "defragment" -> Ok(types.Defragment)
    "update_driver" -> Ok(types.UpdateDriver)
    "repair_permissions" -> Ok(types.RepairPermissions)
    "custom" -> Ok(types.Custom)
    _ -> Error("Unknown step action: " <> s)
  }
}

/// Encode a StepStatus to its JSON string representation.
pub fn encode_step_status(status: types.StepStatus) -> String {
  case status {
    types.StepSuccess -> "success"
    types.StepSkipped -> "skipped"
    types.StepFailed -> "failed"
    types.StepRolledBack -> "rolled_back"
  }
}

/// Encode a Privilege to its JSON string representation.
pub fn encode_privilege(priv: types.Privilege) -> String {
  case priv {
    types.User -> "user"
    types.Admin -> "admin"
    types.Root -> "root"
    types.System -> "system"
  }
}

/// Decode a JSON string to a Privilege.
pub fn decode_privilege(s: String) -> Result(types.Privilege, String) {
  case string.lowercase(s) {
    "user" -> Ok(types.User)
    "admin" -> Ok(types.Admin)
    "root" -> Ok(types.Root)
    "system" -> Ok(types.System)
    _ -> Error("Unknown privilege: " <> s)
  }
}

// ---------------------------------------------------------------------------
// JSON encoding helpers
// ---------------------------------------------------------------------------

/// Encode an Option(String) as a JSON value (string or null).
fn encode_optional_string(opt: Option(String)) -> json.Json {
  case opt {
    Some(s) -> json.string(s)
    None -> json.null()
  }
}

// ---------------------------------------------------------------------------
// Receipt encoding (Composer → JSON)
// ---------------------------------------------------------------------------

/// Encode a StepResult to a JSON value.
pub fn encode_step_result(sr: types.StepResult) -> json.Json {
  json.object([
    #("step_id", json.string(sr.step_id)),
    #("status", json.string(encode_step_status(sr.status))),
    #("what_changed", encode_optional_string(sr.what_changed)),
    #("why_changed", encode_optional_string(sr.why_changed)),
    #("error_message", encode_optional_string(sr.error_message)),
    #("skip_reason", encode_optional_string(sr.skip_reason)),
  ])
}

/// Encode a Receipt to a JSON value.
pub fn encode_receipt(receipt: types.Receipt) -> json.Json {
  json.object([
    #("plan_id", json.string(receipt.plan_id)),
    #("envelope_ref", json.string(receipt.envelope_ref)),
    #("status", json.string(receipt.status)),
    #("items_checked", json.int(receipt.items_checked)),
    #("items_changed", json.int(receipt.items_changed)),
    #("items_failed", json.int(receipt.items_failed)),
    #("items_skipped", json.int(receipt.items_skipped)),
    #("step_results", json.array(receipt.step_results, encode_step_result)),
  ])
}

/// Encode a Receipt to a JSON string.
pub fn receipt_to_json(receipt: types.Receipt) -> String {
  encode_receipt(receipt)
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// ProcedurePlan encoding (for round-trip / forwarding)
// ---------------------------------------------------------------------------

/// Encode a StepTarget to a JSON value.
pub fn encode_step_target(target: types.StepTarget) -> json.Json {
  json.object([
    #("path", encode_optional_string(target.path)),
    #("service", encode_optional_string(target.service)),
    #("registry_key", encode_optional_string(target.registry_key)),
    #("program", encode_optional_string(target.program)),
  ])
}

/// Encode a Step to a JSON value.
pub fn encode_step(step: types.Step) -> json.Json {
  json.object([
    #("step_id", json.string(step.step_id)),
    #("order", json.int(step.order)),
    #("action", json.string(encode_step_action(step.action))),
    #("title", json.string(step.title)),
    #("description", encode_optional_string(step.description)),
    #("preview", encode_optional_string(step.preview)),
    #("risk", json.string(encode_risk_level(step.risk))),
    #("reversibility", json.string(encode_reversibility(step.reversibility))),
    #("undo_instruction", encode_optional_string(step.undo_instruction)),
    #("target", encode_step_target(step.target)),
    #("requires_confirmation", json.bool(step.requires_confirmation)),
    #("estimated_duration_seconds", json.int(step.estimated_duration_seconds)),
    #("finding_refs", json.array(step.finding_refs, json.string)),
  ])
}

/// Encode a Prerequisite to a JSON value.
pub fn encode_prerequisite(prereq: types.Prerequisite) -> json.Json {
  json.object([
    #("check", json.string(prereq.check)),
    #("description", json.string(prereq.description)),
    #("blocking", json.bool(prereq.blocking)),
  ])
}

/// Encode a ProcedurePlan to a JSON value.
pub fn encode_plan(plan: types.ProcedurePlan) -> json.Json {
  json.object([
    #("version", json.string(plan.version)),
    #("plan_id", json.string(plan.plan_id)),
    #("envelope_ref", json.string(plan.envelope_ref)),
    #("title", encode_optional_string(plan.title)),
    #("description", encode_optional_string(plan.description)),
    #("overall_risk", json.string(encode_risk_level(plan.overall_risk))),
    #(
      "overall_reversibility",
      json.string(encode_reversibility(plan.overall_reversibility)),
    ),
    #("estimated_duration_seconds", json.int(plan.estimated_duration_seconds)),
    #("requires_reboot", json.bool(plan.requires_reboot)),
    #(
      "requires_privileges",
      json.array(
        plan.requires_privileges,
        fn(p) { json.string(encode_privilege(p)) },
      ),
    ),
    #("steps", json.array(plan.steps, encode_step)),
    #("prerequisites", json.array(plan.prerequisites, encode_prerequisite)),
    #("warnings", json.array(plan.warnings, json.string)),
    #("approval_required", json.bool(plan.approval_required)),
  ])
}

/// Encode a ProcedurePlan to a JSON string.
pub fn plan_to_json(plan: types.ProcedurePlan) -> String {
  encode_plan(plan)
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// ProcedurePlan decoding (JSON → Composer)
// ---------------------------------------------------------------------------

/// Helper: decode an optional string field from dynamic data.
fn optional_string_field(
  data: dynamic.Dynamic,
  field_name: String,
) -> Result(Option(String), List(dynamic.DecodeError)) {
  case dynamic.field(field_name, dynamic.string)(data) {
    Ok(s) -> Ok(Some(s))
    Error(_) -> Ok(None)
  }
}

/// Helper: decode a required string field from dynamic data.
fn required_string_field(
  data: dynamic.Dynamic,
  field_name: String,
) -> Result(String, String) {
  dynamic.field(field_name, dynamic.string)(data)
  |> result.map_error(fn(_) { "Missing field: " <> field_name })
}

/// Helper: decode a required int field from dynamic data.
fn required_int_field(
  data: dynamic.Dynamic,
  field_name: String,
) -> Result(Int, String) {
  dynamic.field(field_name, dynamic.int)(data)
  |> result.map_error(fn(_) { "Missing field: " <> field_name })
}

/// Helper: decode a required bool field from dynamic data, defaulting to False.
fn bool_field_or_false(
  data: dynamic.Dynamic,
  field_name: String,
) -> Bool {
  case dynamic.field(field_name, dynamic.bool)(data) {
    Ok(b) -> b
    Error(_) -> False
  }
}

/// Decode a StepTarget from dynamic JSON data.
pub fn decode_step_target(
  data: dynamic.Dynamic,
) -> Result(types.StepTarget, String) {
  Ok(types.StepTarget(
    path: case optional_string_field(data, "path") {
      Ok(v) -> v
      Error(_) -> None
    },
    service: case optional_string_field(data, "service") {
      Ok(v) -> v
      Error(_) -> None
    },
    registry_key: case optional_string_field(data, "registry_key") {
      Ok(v) -> v
      Error(_) -> None
    },
    program: case optional_string_field(data, "program") {
      Ok(v) -> v
      Error(_) -> None
    },
  ))
}

/// Decode a Step from dynamic JSON data.
pub fn decode_step(data: dynamic.Dynamic) -> Result(types.Step, String) {
  use step_id <- result.try(required_string_field(data, "step_id"))
  use order <- result.try(required_int_field(data, "order"))
  use action_str <- result.try(required_string_field(data, "action"))
  use action <- result.try(decode_step_action(action_str))
  use title <- result.try(required_string_field(data, "title"))

  let description = case optional_string_field(data, "description") {
    Ok(v) -> v
    Error(_) -> None
  }
  let preview = case optional_string_field(data, "preview") {
    Ok(v) -> v
    Error(_) -> None
  }

  let risk = case required_string_field(data, "risk") {
    Ok(s) ->
      case decode_risk_level(s) {
        Ok(r) -> r
        Error(_) -> types.Safe
      }
    Error(_) -> types.Safe
  }

  let reversibility = case required_string_field(data, "reversibility") {
    Ok(s) ->
      case decode_reversibility(s) {
        Ok(r) -> r
        Error(_) -> types.Full
      }
    Error(_) -> types.Full
  }

  let undo_instruction = case optional_string_field(data, "undo_instruction") {
    Ok(v) -> v
    Error(_) -> None
  }

  let target = case dynamic.field("target", dynamic.dynamic)(data) {
    Ok(t) ->
      case decode_step_target(t) {
        Ok(st) -> st
        Error(_) ->
          types.StepTarget(
            path: None,
            service: None,
            registry_key: None,
            program: None,
          )
      }
    Error(_) ->
      types.StepTarget(
        path: None,
        service: None,
        registry_key: None,
        program: None,
      )
  }

  let requires_confirmation = bool_field_or_false(data, "requires_confirmation")
  let estimated_duration_seconds = case
    required_int_field(data, "estimated_duration_seconds")
  {
    Ok(d) -> d
    Error(_) -> 0
  }

  let finding_refs = case
    dynamic.field("finding_refs", dynamic.list(dynamic.string))(data)
  {
    Ok(refs) -> refs
    Error(_) -> []
  }

  Ok(types.Step(
    step_id: step_id,
    order: order,
    action: action,
    title: title,
    description: description,
    preview: preview,
    risk: risk,
    reversibility: reversibility,
    undo_instruction: undo_instruction,
    target: target,
    requires_confirmation: requires_confirmation,
    estimated_duration_seconds: estimated_duration_seconds,
    finding_refs: finding_refs,
  ))
}

/// Decode a Prerequisite from dynamic JSON data.
pub fn decode_prerequisite(
  data: dynamic.Dynamic,
) -> Result(types.Prerequisite, String) {
  use check <- result.try(required_string_field(data, "check"))
  use description <- result.try(required_string_field(data, "description"))
  let blocking = bool_field_or_false(data, "blocking")
  Ok(types.Prerequisite(check: check, description: description, blocking: blocking))
}

/// Decode a ProcedurePlan from dynamic JSON data.
/// This is the main entry point for consuming plans from HCT/clinician.
pub fn decode_plan(data: dynamic.Dynamic) -> Result(types.ProcedurePlan, String) {
  use version <- result.try(required_string_field(data, "version"))
  use plan_id <- result.try(required_string_field(data, "plan_id"))
  use envelope_ref <- result.try(required_string_field(data, "envelope_ref"))

  let title = case optional_string_field(data, "title") {
    Ok(v) -> v
    Error(_) -> None
  }
  let description = case optional_string_field(data, "description") {
    Ok(v) -> v
    Error(_) -> None
  }

  let overall_risk = case required_string_field(data, "overall_risk") {
    Ok(s) ->
      case decode_risk_level(s) {
        Ok(r) -> r
        Error(_) -> types.Safe
      }
    Error(_) -> types.Safe
  }

  let overall_reversibility = case
    required_string_field(data, "overall_reversibility")
  {
    Ok(s) ->
      case decode_reversibility(s) {
        Ok(r) -> r
        Error(_) -> types.Full
      }
    Error(_) -> types.Full
  }

  let estimated_duration_seconds = case
    required_int_field(data, "estimated_duration_seconds")
  {
    Ok(d) -> d
    Error(_) -> 0
  }

  let requires_reboot = bool_field_or_false(data, "requires_reboot")

  let requires_privileges = case
    dynamic.field("requires_privileges", dynamic.list(dynamic.string))(data)
  {
    Ok(privs) ->
      list.filter_map(privs, fn(p) {
        case decode_privilege(p) {
          Ok(priv) -> Ok(priv)
          Error(_) -> Error(Nil)
        }
      })
    Error(_) -> []
  }

  // Decode steps array
  let steps = case
    dynamic.field("steps", dynamic.list(dynamic.dynamic))(data)
  {
    Ok(step_dyn_list) -> {
      let decoded =
        list.filter_map(step_dyn_list, fn(sd) {
          case decode_step(sd) {
            Ok(step) -> Ok(step)
            Error(_) -> Error(Nil)
          }
        })
      decoded
    }
    Error(_) -> []
  }

  // Decode prerequisites array
  let prerequisites = case
    dynamic.field("prerequisites", dynamic.list(dynamic.dynamic))(data)
  {
    Ok(prereq_dyn_list) ->
      list.filter_map(prereq_dyn_list, fn(pd) {
        case decode_prerequisite(pd) {
          Ok(prereq) -> Ok(prereq)
          Error(_) -> Error(Nil)
        }
      })
    Error(_) -> []
  }

  let warnings = case
    dynamic.field("warnings", dynamic.list(dynamic.string))(data)
  {
    Ok(w) -> w
    Error(_) -> []
  }

  let approval_required = bool_field_or_false(data, "approval_required")

  Ok(types.ProcedurePlan(
    version: version,
    plan_id: plan_id,
    envelope_ref: envelope_ref,
    title: title,
    description: description,
    overall_risk: overall_risk,
    overall_reversibility: overall_reversibility,
    estimated_duration_seconds: estimated_duration_seconds,
    requires_reboot: requires_reboot,
    requires_privileges: requires_privileges,
    steps: steps,
    prerequisites: prerequisites,
    warnings: warnings,
    approval_required: approval_required,
  ))
}

/// Decode a ProcedurePlan from a JSON string.
/// Returns Error if the JSON is malformed or required fields are missing.
pub fn plan_from_json(
  json_string: String,
) -> Result(types.ProcedurePlan, String) {
  case json.decode(json_string, dynamic.dynamic) {
    Ok(data) -> decode_plan(data)
    Error(_) -> Error("Invalid JSON")
  }
}

/// Encode a Receipt to JSON, decode it back, and verify round-trip integrity.
/// Useful for testing and validation.
pub fn receipt_round_trip(receipt: types.Receipt) -> Bool {
  let encoded = receipt_to_json(receipt)
  case json.decode(encoded, dynamic.dynamic) {
    Ok(_) -> True
    Error(_) -> False
  }
}
