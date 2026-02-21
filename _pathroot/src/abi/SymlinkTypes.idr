-- SymlinkTypes.idr
-- Idris2 ABI definitions for POSIX symlink operations
-- SPDX-License-Identifier: PMPL-1.0

module SymlinkTypes

%default total

-- Memory layout guarantees for cross-language compatibility
public export
data SymlinkResult : Type where
  ||| Success with bytes read (for readlink) or 0 (for symlink)
  Success : (bytes : Nat) -> SymlinkResult
  ||| Error with errno value
  Error : (errno : Int) -> SymlinkResult

||| Path must be valid UTF-8 and null-terminated
||| Maximum length 4096 bytes (POSIX PATH_MAX)
public export
record PathString where
  constructor MkPath
  data : String
  {auto prf : LTE (length data) 4096}

||| Proof that path length is within bounds
export
mkPath : (s : String) -> Maybe PathString
mkPath s = case isLTE (length s) 4096 of
  Yes prf => Just (MkPath s @{prf})
  No _ => Nothing

||| Buffer for readlink output
||| Must be at least 4096 bytes to hold any valid path
public export
record PathBuffer where
  constructor MkBuffer
  size : Nat
  {auto prf : LTE 4096 size}

||| Create buffer with compile-time size validation
export
mkBuffer : (n : Nat) -> {auto prf : LTE 4096 n} -> PathBuffer
mkBuffer n = MkBuffer n

-- ABI contract: These functions must be implemented by FFI layer
export
%foreign "C:zig_readlink,libpathroot_abi"
prim_readlink : String -> String -> Int -> Int

export
%foreign "C:zig_symlink,libpathroot_abi"
prim_symlink : String -> Int -> String -> Int -> Int
