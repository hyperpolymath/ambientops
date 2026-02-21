/**
 * _pathroot Validation CLI
 * Validates _pathroot environment configuration
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

open Types
open DenoBindings

/**
 * ANSI color codes
 */
module Colors = {
  let reset = "\x1b[0m"
  let green = "\x1b[32m"
  let yellow = "\x1b[33m"
  let red = "\x1b[31m"
  let cyan = "\x1b[36m"
}

/**
 * Format a validation result for display
 */
let formatResult = (result: validationResult): string => {
  let (color, symbol) = switch result.status {
  | Pass => (Colors.green, "✓")
  | Warn => (Colors.yellow, "⚠")
  | Fail => (Colors.red, "✗")
  }

  `${color}[${symbol}]${Colors.reset} ${result.check}: ${result.message}`
}

/**
 * Run all validation checks
 */
let runValidation = async (): array<validationResult> => {
  let results = []

  // Discover _pathroot
  let discovery = await Discovery.discover()

  Js.Array.push({
    check: "_pathroot exists",
    status: discovery.found ? Pass : Fail,
    message: discovery.found
      ? `Found at ${discovery.pathrootFile->Belt.Option.getWithDefault("")}`
      : "Not found in standard locations",
  }, results)->ignore

  // Early return if not found
  if !discovery.found {
    results
  } else {
    switch discovery.devtoolsRoot {
    | None => results
    | Some(devtoolsRoot) => {
        // Check devtools root exists
        let rootCheck = try {
          let fileInfo = await stat(devtoolsRoot)
          if fileInfo.isDirectory {
            Js.Array.push({
              check: "devtools root exists",
              status: Pass,
              message: devtoolsRoot,
            }, results)->ignore
            true
          } else {
            Js.Array.push({
              check: "devtools root exists",
              status: Fail,
              message: devtoolsRoot,
            }, results)->ignore
            false
          }
        } catch {
        | _ => {
            Js.Array.push({
              check: "devtools root exists",
              status: Fail,
              message: `Directory not found: ${devtoolsRoot}`,
            }, results)->ignore
            false
          }
        }

        // Continue only if root exists
        if !rootCheck {
          results
        } else {
          // Validate directory structure
          let dirValidation = await Discovery.validateDevtoolsRoot(devtoolsRoot)
          if dirValidation["valid"] {
            Js.Array.push({
              check: "directory structure",
              status: Pass,
              message: "All required directories present",
            }, results)->ignore
          } else {
            Js.Array.push({
              check: "directory structure",
              status: Warn,
              message: `Missing: ${Js.Array.joinWith(", ", dirValidation["missing"])}`,
            }, results)->ignore
          }

          // Check _envbase
          let envbase = await Envbase.loadEnvbase(devtoolsRoot)
          switch envbase {
          | Some(eb) => {
              Js.Array.push({
                check: "_envbase exists",
                status: Pass,
                message: `env=${eb.env}, profile=${eb.profile}`,
              }, results)->ignore

              // Validate required fields
              if eb.env != "" && eb.profile != "" {
                Js.Array.push({
                  check: "_envbase schema",
                  status: Pass,
                  message: "All required fields present",
                }, results)->ignore
              } else {
                Js.Array.push({
                  check: "_envbase schema",
                  status: Warn,
                  message: "Missing required fields",
                }, results)->ignore
              }
            }
          | None => {
              Js.Array.push({
                check: "_envbase exists",
                status: Warn,
                message: `Not found at ${Envbase.getEnvbasePath(devtoolsRoot)}`,
              }, results)->ignore
            }
          }

          // Check platform detection
          Js.Array.push({
            check: "platform detection",
            status: Pass,
            message: platformToString(discovery.platform),
          }, results)->ignore

          results
        }
      }
    }
  }
}

/**
 * Main entry point
 */
let main = async (): unit => {
  Js.log(`${Colors.cyan}======================================${Colors.reset}`)
  Js.log(`${Colors.cyan} _pathroot Validation${Colors.reset}`)
  Js.log(`${Colors.cyan}======================================${Colors.reset}`)
  Js.log("")

  let results = await runValidation()

  results->Belt.Array.forEach(result => {
    Js.log(formatResult(result))
  })

  Js.log("")

  let failures = results->Belt.Array.keep(r => r.status == Fail)->Belt.Array.length
  let warnings = results->Belt.Array.keep(r => r.status == Warn)->Belt.Array.length

  Js.log(`Summary: ${Belt.Int.toString(failures)} failures, ${Belt.Int.toString(warnings)} warnings`)

  if failures > 0 {
    exit(1)
  }
}

// Run main
main()->ignore
