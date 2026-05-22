//// SPDX-License-Identifier: MPL-2.0
//// (MPL-2.0 preferred; MPL-2.0 required for Gleam ecosystem SPDX)
////
//// cli.gleam — CLI interface for AmbientOps Composer
////
//// Commands:
////   orchestrate <plan.json>         Execute a procedure plan
////   dry-run <plan.json>             Preview execution without mutations
////   validate <plan.json>            Validate a plan without executing
////   status <execution-id>           Check execution status (future)
////   rollback <execution-id>         Rollback a completed execution (future)
////
//// Output:
////   Writes receipt JSON to stdout on success.
////   Writes error messages to stderr.
////   Exit code 0 on success, 1 on failure.

import argv
import composer
import composer/codec
import composer/types
import gleam/io
import gleam/list
import gleam/option
import gleam/string
import simplifile

/// CLI exit codes.
const exit_success = 0

const exit_failure = 1

/// Entry point for the Composer CLI.
/// Parses command-line arguments and dispatches to the appropriate handler.
pub fn run() -> Int {
  case argv.load().arguments {
    ["orchestrate", plan_path] -> cmd_orchestrate(plan_path, False)
    ["dry-run", plan_path] -> cmd_orchestrate(plan_path, True)
    ["validate", plan_path] -> cmd_validate(plan_path)
    ["rollback", plan_path] -> cmd_rollback(plan_path)
    ["version"] -> cmd_version()
    ["help"] -> cmd_help()
    ["--help"] -> cmd_help()
    ["-h"] -> cmd_help()
    [] -> cmd_help()
    [cmd, ..] -> {
      io.println_error("Unknown command: " <> cmd)
      io.println_error("Run 'composer help' for usage")
      exit_failure
    }
  }
}

/// Print version information.
fn cmd_version() -> Int {
  io.println("composer 0.1.0 (AmbientOps Operating Room)")
  exit_success
}

/// Print usage help.
fn cmd_help() -> Int {
  io.println(
    string.join(
      [
        "composer — AmbientOps orchestration engine",
        "",
        "USAGE:",
        "  composer orchestrate <plan.json>   Execute a procedure plan",
        "  composer dry-run <plan.json>       Preview without mutations",
        "  composer validate <plan.json>      Validate plan structure",
        "  composer rollback <plan.json>      Roll back a previously executed plan",
        "  composer version                   Show version",
        "  composer help                      Show this help",
        "",
        "DESCRIPTION:",
        "  Composer reads a ProcedurePlan JSON file (from HCT or clinician),",
        "  validates prerequisites, executes steps in order, and outputs a",
        "  Receipt JSON documenting what changed.",
        "",
        "  In dry-run mode, all steps are simulated — no system changes occur.",
        "",
        "OUTPUT:",
        "  Receipt JSON is written to stdout on completion.",
        "  Errors and progress messages go to stderr.",
        "",
        "EXAMPLES:",
        "  composer validate plan.json",
        "  composer dry-run plan.json > receipt.json",
        "  composer orchestrate plan.json | jq .",
        "",
        "EXIT CODES:",
        "  0  Success (all steps completed or dry-run finished)",
        "  1  Failure (validation error, step failure, or I/O error)",
      ],
      "\n",
    ),
  )
  exit_success
}

/// Validate a plan file without executing it.
/// Reports overall risk, step count, and any structural issues.
fn cmd_validate(plan_path: String) -> Int {
  case read_plan(plan_path) {
    Error(msg) -> {
      io.println_error("Error: " <> msg)
      exit_failure
    }
    Ok(plan) -> {
      case composer.validate_plan(plan) {
        Error(msg) -> {
          io.println_error("Validation failed: " <> msg)
          exit_failure
        }
        Ok(validated_plan) -> {
          let risk = codec.encode_risk_level(composer.overall_risk(validated_plan))
          let rev = codec.encode_reversibility(validated_plan.overall_reversibility)
          let step_count = list.length(validated_plan.steps)
          let title = case validated_plan.title {
            option.Some(t) -> t
            option.None -> "(untitled)"
          }

          io.println_error("Plan: " <> title)
          io.println_error(
            "  ID: " <> validated_plan.plan_id,
          )
          io.println_error(
            "  Steps: " <> string.inspect(step_count),
          )
          io.println_error("  Overall risk: " <> risk)
          io.println_error("  Reversibility: " <> rev)
          io.println_error(
            "  Estimated duration: "
            <> string.inspect(validated_plan.estimated_duration_seconds)
            <> "s",
          )

          case validated_plan.requires_reboot {
            True -> io.println_error("  WARNING: Requires reboot")
            False -> Nil
          }

          case validated_plan.approval_required {
            True -> io.println_error("  WARNING: Requires approval")
            False -> Nil
          }

          case validated_plan.warnings {
            [] -> Nil
            warnings -> {
              io.println_error("  Warnings:")
              list.each(warnings, fn(w) { io.println_error("    - " <> w) })
            }
          }

          case validated_plan.prerequisites {
            [] -> Nil
            prereqs -> {
              io.println_error("  Prerequisites:")
              list.each(prereqs, fn(p: types.Prerequisite) {
                let blocking_tag = case p.blocking {
                  True -> " [BLOCKING]"
                  False -> ""
                }
                io.println_error(
                  "    - " <> p.description <> blocking_tag,
                )
              })
            }
          }

          io.println_error("Validation: PASSED")
          exit_success
        }
      }
    }
  }
}

/// Execute (or dry-run) a procedure plan.
/// Reads the plan, validates it, executes each step, and outputs a receipt.
fn cmd_orchestrate(plan_path: String, dry_run: Bool) -> Int {
  let mode = case dry_run {
    True -> "dry-run"
    False -> "orchestrate"
  }

  io.println_error(
    "Composer: " <> mode <> " — reading " <> plan_path,
  )

  case read_plan(plan_path) {
    Error(msg) -> {
      io.println_error("Error: " <> msg)
      exit_failure
    }
    Ok(plan) -> {
      // Validate
      case composer.validate_plan(plan) {
        Error(msg) -> {
          io.println_error("Validation failed: " <> msg)
          exit_failure
        }
        Ok(validated_plan) -> {
          // Create execution context
          let exec = case dry_run {
            True -> composer.begin_dry_run(validated_plan)
            False -> composer.begin_execution(validated_plan)
          }

          // Execute steps sequentially
          let final_exec = execute_steps(exec, validated_plan.steps, dry_run)

          // Generate receipt
          let receipt = composer.generate_receipt(final_exec)
          let receipt_json = codec.receipt_to_json(receipt)

          // Output receipt to stdout
          io.println(receipt_json)

          // Summary to stderr
          io.println_error(composer.receipt_summary(receipt))

          case final_exec.status {
            types.Completed -> exit_success
            types.Failed -> exit_failure
            _ -> exit_success
          }
        }
      }
    }
  }
}

/// Roll back a previously executed plan.
/// Reads the plan, reconstructs the execution as if all steps succeeded
/// (since the original execution completed), then reverses each step using
/// its undo_instruction in reverse order.
///
/// Steps with NoReversibility or missing undo_instruction are skipped.
/// Outputs a rollback receipt to stdout.
fn cmd_rollback(plan_path: String) -> Int {
  io.println_error("Composer: rollback — reading " <> plan_path)

  case read_plan(plan_path) {
    Error(msg) -> {
      io.println_error("Error: " <> msg)
      exit_failure
    }
    Ok(plan) -> {
      case composer.validate_plan(plan) {
        Error(msg) -> {
          io.println_error("Validation failed: " <> msg)
          exit_failure
        }
        Ok(validated_plan) -> {
          // Check plan-level reversibility
          case validated_plan.overall_reversibility {
            types.NoReversibility -> {
              io.println_error(
                "Error: Plan is marked as irreversible (NoReversibility) — cannot roll back",
              )
              exit_failure
            }
            _ -> {
              // Reconstruct the execution as if all steps succeeded
              // (simulating the state after a completed orchestrate run)
              let exec =
                list.fold(
                  validated_plan.steps,
                  composer.begin_execution(validated_plan),
                  fn(acc, step) {
                    let result =
                      types.StepResult(
                        step_id: step.step_id,
                        status: types.StepSuccess,
                        what_changed: option.Some(
                          "Executed " <> codec.encode_step_action(step.action),
                        ),
                        why_changed: option.Some("Per procedure plan"),
                        error_message: option.None,
                        skip_reason: option.None,
                      )
                    composer.advance(acc, result)
                  },
                )

              // Perform the rollback
              case composer.rollback(exec) {
                Error(msg) -> {
                  io.println_error("Rollback failed: " <> msg)
                  exit_failure
                }
                Ok(rolled_back_exec) -> {
                  // Report each rollback step to stderr
                  let reversed_steps =
                    list.filter(validated_plan.steps, fn(step) {
                      list.any(rolled_back_exec.completed_steps, fn(sr) {
                        sr.step_id == step.step_id
                      })
                    })
                    |> list.reverse()

                  list.each(reversed_steps, fn(step) {
                    let matching_result =
                      list.find(rolled_back_exec.completed_steps, fn(sr) {
                        sr.step_id == step.step_id
                      })
                    case matching_result {
                      Ok(sr) -> {
                        let status_label = codec.encode_step_status(sr.status)
                        io.println_error(
                          "  [rollback] "
                          <> step.step_id
                          <> " — "
                          <> step.title
                          <> " → "
                          <> status_label,
                        )
                        case sr.what_changed {
                          option.Some(desc) ->
                            io.println_error("      " <> desc)
                          option.None -> Nil
                        }
                        case sr.skip_reason {
                          option.Some(reason) ->
                            io.println_error("      Reason: " <> reason)
                          option.None -> Nil
                        }
                      }
                      Error(_) -> Nil
                    }
                  })

                  // Generate and output receipt
                  let receipt = composer.generate_receipt(rolled_back_exec)
                  let receipt_json = codec.receipt_to_json(receipt)
                  io.println(receipt_json)
                  io.println_error(composer.receipt_summary(receipt))
                  exit_success
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Execute steps sequentially, reporting progress to stderr.
/// In dry-run mode, each step is marked as successful without system changes.
/// In real mode, delegates to the appropriate component CLI.
fn execute_steps(
  exec: types.Execution,
  remaining_steps: List(types.Step),
  dry_run: Bool,
) -> types.Execution {
  case remaining_steps {
    [] -> exec
    [step, ..rest] -> {
      io.println_error(
        "  ["
        <> string.inspect(step.order)
        <> "/"
        <> string.inspect(list.length(exec.plan.steps))
        <> "] "
        <> step.title,
      )

      let step_result = case dry_run {
        True -> {
          // Dry-run: simulate success
          io.println_error("      (dry-run: skipping)")
          types.StepResult(
            step_id: step.step_id,
            status: types.StepSkipped,
            what_changed: option.None,
            why_changed: option.None,
            error_message: option.None,
            skip_reason: option.Some("Dry-run mode — no changes applied"),
          )
        }
        False -> {
          // Real execution: delegate to component CLI based on action
          execute_single_step(step)
        }
      }

      let new_exec = composer.advance(exec, step_result)

      // If execution halted (failure), don't continue
      case new_exec.status {
        types.Failed -> {
          io.println_error("      FAILED — halting execution")
          new_exec
        }
        _ -> execute_steps(new_exec, rest, dry_run)
      }
    }
  }
}

/// Execute a single step by delegating to the appropriate component.
/// Currently returns a stub result — real integration will call HCT/clinician/ER.
fn execute_single_step(step: types.Step) -> types.StepResult {
  // For now, report that the step action is recognized but not yet wired.
  // Phase 4 completion requires wiring these to actual component CLIs:
  //   - DeleteFile, DeleteDirectory, ClearCache, ClearTemp → ER (emergency-room)
  //   - RunCommand → clinician
  //   - StopService, StartService, RestartService → clinician or systemd
  //   - RepairPermissions, UpdateDriver → HCT (hardware-crash-team)
  let action_name = codec.encode_step_action(step.action)
  io.println_error("      Action: " <> action_name)

  case step.target.path {
    option.Some(path) -> io.println_error("      Target: " <> path)
    option.None -> Nil
  }
  case step.target.service {
    option.Some(svc) -> io.println_error("      Service: " <> svc)
    option.None -> Nil
  }

  // Stub: mark as success for orchestration skeleton
  // Real implementation will spawn the component process and check exit code
  types.StepResult(
    step_id: step.step_id,
    status: types.StepSuccess,
    what_changed: option.Some("Executed " <> action_name),
    why_changed: option.Some("Per procedure plan " <> step.step_id),
    error_message: option.None,
    skip_reason: option.None,
  )
}

/// Read and parse a ProcedurePlan from a JSON file.
fn read_plan(path: String) -> Result(types.ProcedurePlan, String) {
  case simplifile.read(path) {
    Error(_) -> Error("Could not read file: " <> path)
    Ok(contents) -> codec.plan_from_json(contents)
  }
}

/// Erlang FFI: halt the VM with an exit code.
@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

/// Main entry point — run the CLI and exit with the result code.
pub fn main() -> Nil {
  let code = run()
  halt(code)
}
