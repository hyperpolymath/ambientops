/**
 * nicaug - CLI Entry Point
 * Command-line interface for Nickel-Augmented deployment
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

open NickelTypes
open NickelParser
open PlatformOrchestrator

/**
 * CLI Commands
 */
type cliCommand =
  | Build
  | Deploy
  | Validate
  | Info
  | Help
  | Version

/**
 * Parse CLI arguments
 */
let parseArgs = (args: array<string>): (cliCommand, array<string>) => {
  if Belt.Array.length(args) == 0 {
    (Help, [])
  } else {
    let cmd = Belt.Array.getExn(args, 0)
    let rest = Belt.Array.sliceToEnd(args, 1)

    let command = switch cmd {
    | "build" => Build
    | "deploy" => Deploy
    | "validate" => Validate
    | "info" => Info
    | "--version" | "-v" => Version
    | "--help" | "-h" | _ => Help
    }

    (command, rest)
  }
}

/**
 * Print help message
 */
let printHelp = (): unit => {
  Js.log("nicaug - Nickel-Augmented Configuration Engine v0.1.0")
  Js.log("")
  Js.log("Usage: nicaug <command> [options]")
  Js.log("")
  Js.log("Commands:")
  Js.log("  build      Build deployment plan from Mustfile")
  Js.log("  deploy     Execute deployment")
  Js.log("  validate   Validate Nickel contracts")
  Js.log("  info       Show platform detection info")
  Js.log("")
  Js.log("Options:")
  Js.log("  -h, --help     Show this help message")
  Js.log("  -v, --version  Show version")
  Js.log("")
  Js.log("Examples:")
  Js.log("  nicaug info              # Show detected platform")
  Js.log("  nicaug validate          # Validate Mustfile")
  Js.log("  nicaug build             # Generate deployment plan")
  Js.log("  nicaug deploy            # Execute deployment")
}

/**
 * Print version
 */
let printVersion = (): unit => {
  Js.log("nicaug v0.1.0")
  Js.log("Nickel-Augmented Configuration Engine")
  Js.log("Part of the Rhodium Standard (_pathroot project)")
}

/**
 * Show platform info
 */
let showInfo = (): unit => {
  let platform = detectPlatform()

  Js.log("Platform Detection:")
  Js.log(`  OS: ${platform.os}`)
  Js.log(`  Arch: ${platform.arch}`)
  Js.log(`  Immutable: ${platform.isImmutable ? "yes" : "no"}`)

  let targetStr = switch platform.targetType {
  | EdgeASIC => "Edge ASIC / Minix"
  | KinoiteLayered => "Fedora Kinoite (Layered)"
  | AppleDarwin => "Apple Darwin (macOS)"
  | StandardPC => "Standard PC (Linux)"
  }

  Js.log(`  Target Type: ${targetStr}`)
  Js.log(`  Priority Route: ${platform.deploymentPriority}`)
}

/**
 * Validate Mustfile
 */
let validateMustfile = async (): int => {
  Js.log("Validating Mustfile...")

  let result = await loadMustfile("./Mustfile")

  switch result {
  | Ok(config) => {
      Js.log("✓ Mustfile is valid")

      switch config.project {
      | Some(proj) => {
          Js.log("\nProject:")
          Js.log(`  Name: ${proj.name}`)
          Js.log(`  Alias: ${proj.shortAlias}`)
          Js.log(`  Version: ${proj.version}`)
          Js.log(`  Stability: ${stabilityToString(proj.stability)}`)
        }
      | None => Js.log("  (No project section)")
      }

      0
    }
  | Error(err) => {
      Js.log(`✗ Validation failed: ${err}`)
      1
    }
  }
}

/**
 * Build deployment plan
 */
let buildPlan = async (): int => {
  Js.log("Building deployment plan...")

  let platform = detectPlatform()
  let config = await loadMustfile("./Mustfile")

  switch config {
  | Ok(cfg) => {
      // Example packages for demonstration
      let packages = ["git", "curl", "wget"]

      let commands = orchestrate(platform, cfg, packages)

      Js.log(`\nGenerated ${Belt.Int.toString(Belt.Array.length(commands))} deployment commands:\n`)

      commands->Belt.Array.forEach(cmd => {
        Js.log(`[${cmd.platform}] ${cmd.description}`)
        Js.log(`  ${cmd.command} ${Js.Array.joinWith(" ", cmd.args)}`)
        Js.log("")
      })

      0
    }
  | Error(err) => {
      Js.log(`✗ Failed to load Mustfile: ${err}`)
      1
    }
  }
}

/**
 * Main entry point
 */
let main = async (): unit => {
  open! DenoBindings

  let args = %raw(`Deno.args`)
  let (command, _options) = parseArgs(args)

  let exitCode = switch command {
  | Help => {
      printHelp()
      0
    }
  | Version => {
      printVersion()
      0
    }
  | Info => {
      showInfo()
      0
    }
  | Validate => await validateMustfile()
  | Build => await buildPlan()
  | Deploy => {
      Js.log("Deploy command not yet implemented")
      Js.log("Use 'nicaug build' to see deployment plan")
      1
    }
  }

  exit(exitCode)
}

// Run main
main()->ignore
