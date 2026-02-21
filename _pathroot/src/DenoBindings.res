/**
 * Deno API bindings for ReScript
 * External bindings to Deno runtime APIs
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

// Deno global object
type denoGlobal

@val external deno: denoGlobal = "Deno"

// Deno.build
type build = {os: string}

@get external getBuild: denoGlobal => build = "build"
let build = getBuild(deno)

// Deno.env
module Env = {
  type envType
  @get external getEnv: denoGlobal => envType = "env"
  @send external get: (envType, string) => option<string> = "get"

  let get = (key: string) => get(getEnv(deno), key)
}

// Deno.stat
type fileInfo = {
  isFile: bool,
  isDirectory: bool,
}

@send external stat: (denoGlobal, string) => promise<fileInfo> = "stat"
let stat = (path: string) => stat(deno, path)

// Deno.readTextFile
@send external _readTextFile: (denoGlobal, string) => promise<string> = "readTextFile"
let readTextFile = (path: string) => _readTextFile(deno, path)

// Deno.writeTextFile
@send external _writeTextFile: (denoGlobal, string, string) => promise<unit> = "writeTextFile"
let writeTextFile = (path: string, content: string) => _writeTextFile(deno, path, content)

// Deno.readTextFileSync
@send external _readTextFileSync: (denoGlobal, string) => string = "readTextFileSync"
let readTextFileSync = (path: string) => _readTextFileSync(deno, path)

// Deno.exit
@send external _exit: (denoGlobal, int) => unit = "exit"
let exit = (code: int) => _exit(deno, code)

// @std/path bindings
@module("@std/path") external join: (string, string) => string = "join"
@module("@std/path") external joinMany: array<string> => string = "join"
