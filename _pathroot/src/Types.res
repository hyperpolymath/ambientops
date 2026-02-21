/**
 * _pathroot ReScript Type Definitions
 * Cross-platform devtools environment management
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

/**
 * Platform identifiers
 */
type platform =
  | Windows
  | Linux
  | Darwin
  | WSL

/**
 * TUI configuration options
 */
type tuiConfig = {
  theme: option<[#dark | #light]>,
  logLines: option<int>,
  autoValidate: option<bool>,
}

/**
 * Environment metadata stored in _envbase
 */
type envBase = {
  env: string,
  profile: string,
  platform: platform,
  version: option<string>,
  created: option<string>,
  tui: option<tuiConfig>,
}

/**
 * Discovery result from finding _pathroot
 */
type discoveryResult = {
  found: bool,
  pathrootFile: option<string>,
  devtoolsRoot: option<string>,
  platform: platform,
}

/**
 * Validation result status
 */
type validationStatus =
  | Pass
  | Warn
  | Fail

/**
 * Validation result for environment checks
 */
type validationResult = {
  check: string,
  status: validationStatus,
  message: string,
}

/**
 * Transaction command type
 */
type transactionCommandType =
  | QueryEnv
  | SetProfile
  | Link
  | AuditLinks
  | PathAdd
  | PathRemove

/**
 * Transaction command for TUI protocol
 */
type transactionCommand = {
  @as("type") type_: transactionCommandType,
  params: option<array<string>>,
}

/**
 * Transaction response status
 */
type transactionResponseStatus =
  | Ok
  | Error
  | Warning

/**
 * Transaction response from TUI
 */
type transactionResponse = {
  status: transactionResponseStatus,
  command: string,
  result: Js.Dict.t<Js.Json.t>,
}

/**
 * Symbolic link status
 */
type symLinkStatus =
  | Valid
  | Broken
  | Missing

/**
 * Symbolic link definition
 */
type symLink = {
  source: string,
  destination: string,
  status: option<symLinkStatus>,
}

/**
 * PATH entry with validation
 */
type pathEntry = {
  path: string,
  exists: bool,
  index: int,
}

// Helper functions for JSON encoding/decoding

let platformToString = (platform: platform): string => {
  switch platform {
  | Windows => "windows"
  | Linux => "linux"
  | Darwin => "darwin"
  | WSL => "wsl"
  }
}

let platformFromString = (str: string): option<platform> => {
  switch str {
  | "windows" => Some(Windows)
  | "linux" => Some(Linux)
  | "darwin" => Some(Darwin)
  | "wsl" => Some(WSL)
  | _ => None
  }
}

let validationStatusToString = (status: validationStatus): string => {
  switch status {
  | Pass => "pass"
  | Warn => "warn"
  | Fail => "fail"
  }
}
