/**
 * _pathroot Envbase Module
 * Handles _envbase JSON parsing and manipulation
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

open Types
open DenoBindings

/**
 * Get the path to the _envbase file
 */
let getEnvbasePath = (devtoolsRoot: string): string => {
  join(devtoolsRoot, "_envbase")
}

/**
 * Decode EnvBase from JSON
 */
let decodeEnvBase = (json: Js.Json.t): option<envBase> => {
  open! Js.Json

  switch classify(json) {
  | JSONObject(dict) => {
      let env = Js.Dict.get(dict, "env")->Belt.Option.flatMap(decodeString)
      let profile = Js.Dict.get(dict, "profile")->Belt.Option.flatMap(decodeString)
      let platformStr = Js.Dict.get(dict, "platform")->Belt.Option.flatMap(decodeString)
      let platform = platformStr->Belt.Option.flatMap(platformFromString)
      let version = Js.Dict.get(dict, "version")->Belt.Option.flatMap(decodeString)
      let created = Js.Dict.get(dict, "created")->Belt.Option.flatMap(decodeString)

      switch (env, profile, platform) {
      | (Some(e), Some(p), Some(pl)) => Some({
          env: e,
          profile: p,
          platform: pl,
          version: version,
          created: created,
          tui: None, // TODO: decode tui config
        })
      | _ => None
      }
    }
  | _ => None
  }
}

/**
 * Encode EnvBase to JSON
 */
let encodeEnvBase = (envbase: envBase): Js.Json.t => {
  let dict = Js.Dict.empty()
  Js.Dict.set(dict, "env", Js.Json.string(envbase.env))
  Js.Dict.set(dict, "profile", Js.Json.string(envbase.profile))
  Js.Dict.set(dict, "platform", Js.Json.string(platformToString(envbase.platform)))

  switch envbase.version {
  | Some(v) => Js.Dict.set(dict, "version", Js.Json.string(v))
  | None => ()
  }

  switch envbase.created {
  | Some(c) => Js.Dict.set(dict, "created", Js.Json.string(c))
  | None => ()
  }

  Js.Json.object_(dict)
}

/**
 * Load _envbase from disk
 */
let loadEnvbase = async (devtoolsRoot: string): option<envBase> => {
  let path = getEnvbasePath(devtoolsRoot)

  try {
    let content = await readTextFile(path)
    let json = Js.Json.parseExn(content)
    decodeEnvBase(json)
  } catch {
  | _ => None
  }
}

/**
 * Save _envbase to disk
 */
let saveEnvbase = async (devtoolsRoot: string, envbase: envBase): unit => {
  let path = getEnvbasePath(devtoolsRoot)
  let json = encodeEnvBase(envbase)
  let content = Js.Json.stringifyWithSpace(json, 2) ++ "\n"
  await writeTextFile(path, content)
}

/**
 * Create a default _envbase configuration
 */
let createDefaultEnvbase = (platform: option<platform>): envBase => {
  let platformValue = switch platform {
  | Some(p) => p
  | None => Discovery.detectPlatform()
  }

  {
    env: "devtools",
    profile: "default",
    platform: platformValue,
    version: Some("0.1.0"),
    created: Some(Js.Date.make()->Js.Date.toISOString),
    tui: None,
  }
}

/**
 * Switch to a different profile
 */
let switchProfile = async (devtoolsRoot: string, profileName: string): unit => {
  let envbase = await loadEnvbase(devtoolsRoot)

  switch envbase {
  | Some(eb) => {
      let updated = {...eb, profile: profileName}
      await saveEnvbase(devtoolsRoot, updated)
    }
  | None => Js.Exn.raiseError("_envbase not found")
  }
}

/**
 * Update _envbase with partial values
 */
let updateEnvbase = async (
  devtoolsRoot: string,
  updates: envBase => envBase,
): envBase => {
  let existing = await loadEnvbase(devtoolsRoot)
  let base = switch existing {
  | Some(e) => e
  | None => createDefaultEnvbase(None)
  }

  let envbase = updates(base)
  await saveEnvbase(devtoolsRoot, envbase)
  envbase
}
