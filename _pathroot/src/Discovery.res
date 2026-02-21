/**
 * _pathroot Discovery Module
 * Cross-platform discovery of _pathroot marker files
 *
 * SPDX-License-Identifier: PMPL-1.0-or-later
 */

open Types
open DenoBindings

/**
 * Platform-specific search paths for _pathroot
 */
let getSearchPaths = (platform: platform): array<string> => {
  let home = Env.get("HOME")->Belt.Option.getWithDefault("")

  switch platform {
  | Windows => ["C:\\_pathroot", "D:\\_pathroot"]
  | WSL => ["/mnt/c/_pathroot", "/mnt/d/_pathroot", "/_pathroot"]
  | Linux => ["/_pathroot", join(home, ".pathroot")]
  | Darwin => ["/_pathroot", join(home, ".pathroot")]
  }
}

/**
 * Detect the current platform
 */
let detectPlatform = (): platform => {
  let os = build.os

  if os == "windows" {
    Windows
  } else if os == "darwin" {
    Darwin
  } else {
    // Check for WSL
    try {
      let versionFile = readTextFileSync("/proc/version")
      if (
        Js.String.includes("Microsoft", versionFile) ||
        Js.String.includes("WSL", versionFile)
      ) {
        WSL
      } else {
        Linux
      }
    } catch {
    | _ => Linux
    }
  }
}

/**
 * Check if a file exists and is readable
 */
let fileExists = async (path: string): bool => {
  try {
    let fileInfo = await stat(path)
    fileInfo.isFile
  } catch {
  | _ => false
  }
}

/**
 * Read the devtools root from a _pathroot file
 */
let readPathrootContent = async (path: string): option<string> => {
  try {
    let content = await readTextFile(path)
    let trimmed = content->String.trim
    let cleaned = Js.String.replaceByRe(%re("/\r?\n/g"), "", trimmed)
    Some(cleaned)
  } catch {
  | _ => None
  }
}

/**
 * Discover the _pathroot file and devtools root
 */
let discover = async (): discoveryResult => {
  let platform = detectPlatform()
  let searchPaths = getSearchPaths(platform)

  let rec searchLoop = async (paths: array<string>, index: int): discoveryResult => {
    if index >= Belt.Array.length(paths) {
      {
        found: false,
        pathrootFile: None,
        devtoolsRoot: None,
        platform: platform,
      }
    } else {
      let pathrootPath = Belt.Array.getExn(paths, index)
      let exists = await fileExists(pathrootPath)

      if exists {
        let devtoolsRoot = await readPathrootContent(pathrootPath)
        switch devtoolsRoot {
        | Some(root) =>
          {
            found: true,
            pathrootFile: Some(pathrootPath),
            devtoolsRoot: Some(root),
            platform: platform,
          }
        | None => await searchLoop(paths, index + 1)
        }
      } else {
        await searchLoop(paths, index + 1)
      }
    }
  }

  await searchLoop(searchPaths, 0)
}

/**
 * Validate a devtools root directory
 */
let validateDevtoolsRoot = async (root: string): {
  "valid": bool,
  "missing": array<string>,
} => {
  let requiredDirs = ["bin", "scripts", "config", "logs", "temp", "tools"]
  let missing = []

  let checkDir = async (dir: string): unit => {
    let dirPath = join(root, dir)
    try {
      let fileInfo = await stat(dirPath)
      if !fileInfo.isDirectory {
        Js.Array.push(dir, missing)->ignore
      }
    } catch {
    | _ => Js.Array.push(dir, missing)->ignore
    }
  }

  // Check all directories sequentially
  let _ = await checkDir(Belt.Array.getExn(requiredDirs, 0))
  let _ = await checkDir(Belt.Array.getExn(requiredDirs, 1))
  let _ = await checkDir(Belt.Array.getExn(requiredDirs, 2))
  let _ = await checkDir(Belt.Array.getExn(requiredDirs, 3))
  let _ = await checkDir(Belt.Array.getExn(requiredDirs, 4))
  let _ = await checkDir(Belt.Array.getExn(requiredDirs, 5))

  {
    "valid": Belt.Array.length(missing) == 0,
    "missing": missing,
  }
}
