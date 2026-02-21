/**
 * _pathroot - Modular Devtools Environment Management
 *
 * A cross-platform system for managing development tool environments
 * with discoverable paths, environment metadata, and automation support.
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 *
 * @example
 * ```rescript
 * let result = await Discovery.discover()
 * if result.found {
 *   switch result.devtoolsRoot {
 *   | Some(root) => {
 *       let envbase = await Envbase.loadEnvbase(root)
 *       switch envbase {
 *       | Some(eb) => Js.log(`Profile: ${eb.profile}`)
 *       | None => Js.log("No envbase found")
 *       }
 *     }
 *   | None => Js.log("No devtools root")
 *   }
 * }
 * ```
 *
 * @module
 */

// Re-export all public modules
include Types
include Discovery
include Envbase
