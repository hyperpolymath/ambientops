/**
 * nicaug - Nickel Parser
 * Simplified Nickel configuration parser
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

open NickelTypes

/**
 * Parse a Nickel file (simplified JSON-like syntax for now)
 * Full Nickel parsing would require a proper lexer/parser
 */
let parseFile = async (filePath: string): result<Js.Json.t, string> => {
  open! DenoBindings

  try {
    let content = await readTextFile(filePath)

    // For now, assume Nickel files are JSON-compatible
    // TODO: Implement full Nickel parser
    try {
      let json = Js.Json.parseExn(content)
      Ok(json)
    } catch {
    | Js.Exn.Error(err) =>
        Error(`JSON parse error: ${Js.Exn.message(err)->Belt.Option.getWithDefault("unknown")}`)
    }
  } catch {
  | _ => Error(`Failed to read file: ${filePath}`)
  }
}

/**
 * Parse project schema from JSON
 */
let parseProject = (json: Js.Json.t): result<projectSchema, string> => {
  open! Js.Json

  switch classify(json) {
  | JSONObject(dict) => {
      let name = Js.Dict.get(dict, "name")->Belt.Option.flatMap(decodeString)
      let shortAlias = Js.Dict.get(dict, "short_alias")->Belt.Option.flatMap(decodeString)
      let version = Js.Dict.get(dict, "version")->Belt.Option.flatMap(decodeString)
      let stabilityStr = Js.Dict.get(dict, "stability")
        ->Belt.Option.flatMap(decodeString)
        ->Belt.Option.getWithDefault("Alpha")

      let stability = switch stabilityStr {
      | "Beta" => #Beta
      | "Stable" => #Stable
      | "LTS" => #LTS
      | _ => #Alpha
      }

      switch (name, shortAlias, version) {
      | (Some(n), Some(sa), Some(v)) => Ok({
          name: n,
          shortAlias: sa,
          version: v,
          stability: stability,
        })
      | _ => Error("Missing required fields in project schema")
      }
    }
  | _ => Error("Expected object for project schema")
  }
}

/**
 * Detect platform environment
 */
let detectPlatform = (): platformEnv => {
  open! DenoBindings

  let os = build.os
  let isImmutable = Env.get("RHODIUM_IMMUTABLE")
    ->Belt.Option.map(s => s == "true")
    ->Belt.Option.getWithDefault(false)

  let targetType = if os == "minix" {
    EdgeASIC
  } else if isImmutable {
    KinoiteLayered
  } else if os == "darwin" {
    AppleDarwin
  } else {
    StandardPC
  }

  let deploymentPriority = switch targetType {
  | EdgeASIC => "static_bin"
  | KinoiteLayered => "podman_ostree"
  | StandardPC => "nala_native"
  | AppleDarwin => "brew_native"
  }

  {
    os: os,
    arch: "x86_64",  // TODO: Detect actual arch
    isImmutable: isImmutable,
    targetType: targetType,
    deploymentPriority: deploymentPriority,
  }
}

/**
 * Load and parse Mustfile configuration
 */
let loadMustfile = async (mustfilePath: string): result<nickelConfig, string> => {
  try {
    let json = await parseFile(mustfilePath)

    switch json {
    | Ok(j) => {
        // Parse project section if it exists
        let project = switch Js.Json.classify(j) {
        | JSONObject(dict) =>
            Js.Dict.get(dict, "project")
            ->Belt.Option.flatMap(pj => switch parseProject(pj) {
              | Ok(p) => Some(p)
              | Error(_) => None
            })
        | _ => None
        }

        Ok({
          project: project,
          deployment: None,  // TODO: Parse deployment section
        })
      }
    | Error(e) => Error(e)
    }
  } catch {
  | _ => Error("Failed to load Mustfile")
  }
}
