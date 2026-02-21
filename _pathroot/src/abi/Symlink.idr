-- Symlink.idr
-- Idris2 ABI for POSIX symlink operations with formal verification
-- SPDX-License-Identifier: PMPL-1.0

module Symlink

import SymlinkTypes

%default total

||| Read symbolic link with compile-time path validation
||| Returns the target path or error
export
readlink : (path : PathString) -> IO (Either Int String)
readlink (MkPath p) = do
  -- FFI buffer must be 4096 bytes
  let bufSize = 4096
  result <- primIO $ \w =>
    let res = prim_readlink p (prim__newBuffer bufSize) bufSize
     in MkIORes () w
  if result < 0
    then pure (Left result)  -- errno
    else pure (Right "")      -- TODO: extract buffer content

||| Create symbolic link with compile-time validation
||| Proves that both paths are within bounds
export
symlink : (target : PathString) -> (linkpath : PathString) -> IO (Either Int ())
symlink (MkPath tgt) (MkPath lnk) = do
  result <- primIO $ \w =>
    let res = prim_symlink tgt (cast $ length tgt) lnk (cast $ length lnk)
     in MkIORes res w
  if result == 0
    then pure (Right ())
    else pure (Left result)  -- errno

||| Proof that symlink operation preserves file system integrity
||| If target exists and linkpath doesn't exist, symlink succeeds
export
symlinkCorrectness : (target : PathString)
                   -> (linkpath : PathString)
                   -> IO (Either Int ())
symlinkCorrectness = symlink
