/**
 * nicaug - Nickel Types
 * Type definitions for Nickel contracts
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

/**
 * Nickel value types
 */
type rec nickelValue =
  | NString(string)
  | NNumber(float)
  | NBool(bool)
  | NArray(array<nickelValue>)
  | NRecord(Js.Dict.t<nickelValue>)
  | NEnum(string)  // e.g., 'Alpha, 'Beta
  | NNull

/**
 * Nickel contract types
 */
type rec contractType =
  | TString
  | TNumber
  | TBool
  | TArray(contractType)
  | TRecord(dict<fieldSpec>)
  | TEnum(array<string>)
  | TAny

/**
 * Field specification in a record contract
 */
and fieldSpec = {
  fieldType: contractType,
  optional: bool,
  defaultValue: option<nickelValue>,
}

/**
 * Project schema (from schema.ncl)
 */
type projectSchema = {
  name: string,
  shortAlias: string,
  version: string,
  stability: [#Alpha | #Beta | #Stable | #LTS],
}

/**
 * Cloud mount configuration
 */
type cloudMount = {
  name: string,
  path: string,
  protocol: [#rclone | #fuse | #nfs],
}

/**
 * Deployment schema
 */
type deploymentSchema = {
  priorityRoute: [#podman | #nala | #ostree | #native],
  targets: array<string>,
  cloudMounts: array<cloudMount>,
}

/**
 * Complete configuration
 */
type nickelConfig = {
  project: option<projectSchema>,
  deployment: option<deploymentSchema>,
}

/**
 * Target system type (from os_detect.ncl)
 */
type targetType =
  | EdgeASIC
  | KinoiteLayered
  | AppleDarwin
  | StandardPC

/**
 * Platform detection result
 */
type platformEnv = {
  os: string,
  arch: string,
  isImmutable: bool,
  targetType: targetType,
  deploymentPriority: string,
}

/**
 * Contract validation result
 */
type validationResult =
  | Valid
  | Invalid(array<string>)  // Array of error messages

/**
 * Helper: Convert stability enum to string
 */
let stabilityToString = (stability: [#Alpha | #Beta | #Stable | #LTS]): string => {
  switch stability {
  | #Alpha => "Alpha"
  | #Beta => "Beta"
  | #Stable => "Stable"
  | #LTS => "LTS"
  }
}

/**
 * Helper: Convert protocol enum to string
 */
let protocolToString = (protocol: [#rclone | #fuse | #nfs]): string => {
  switch protocol {
  | #rclone => "rclone"
  | #fuse => "fuse"
  | #nfs => "nfs"
  }
}

/**
 * Helper: Convert priority route to string
 */
let priorityRouteToString = (route: [#podman | #nala | #ostree | #native]): string => {
  switch route {
  | #podman => "podman"
  | #nala => "nala"
  | #ostree => "ostree"
  | #native => "native"
  }
}
