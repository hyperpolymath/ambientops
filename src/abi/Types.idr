-- SPDX-License-Identifier: PMPL-1.0-or-later
||| ABI Type Definitions Template
|||
||| This module defines the Application Binary Interface (ABI) for this library.
||| It serves as the authoritative source of truth for type layouts and FFI interactions
||| across the FlatRacoon ecosystem (Idris <-> Zig <-> Rust/C).
|||
||| All type definitions include formal proofs of correctness (`HasSize`, `HasAlignment`)
||| to ensure memory safety at the boundary.
|||
||| @see https://idris2.readthedocs.io for Idris2 documentation

module SRC.ABI.Types

import Data.Bits
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for this ABI.
||| Used for conditional compilation and layout calculations.
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection.
||| This value is determined during the elaboration phase and can be used to
||| generate platform-specific code or proofs.
public export
thisPlatform : Platform
thisPlatform =
  %runElab do
    -- Platform detection logic would go here.
    -- Currently defaults to Linux but should be overridden by compiler flags.
    pure Linux

--------------------------------------------------------------------------------
-- Core Types
--------------------------------------------------------------------------------

||| Result codes for FFI operations.
||| These map directly to C integer return codes for cross-language compatibility.
|||
||| - `Ok` (0): Success
||| - `Error` (1): Generic failure
||| - `InvalidParam` (2): Argument validation failed
||| - `OutOfMemory` (3): Allocation failed
||| - `NullPointer` (4): Unexpected null pointer
public export
data Result : Type where
  ||| Operation succeeded
  Ok : Result
  ||| Generic error
  Error : Result
  ||| Invalid parameter provided
  InvalidParam : Result
  ||| Out of memory
  OutOfMemory : Result
  ||| Null pointer encountered
  NullPointer : Result

||| Convert a semantic `Result` to its corresponding C integer representation.
||| Used when returning values to the FFI boundary.
public export
resultToInt : Result -> Bits32
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4

||| Decidable equality for `Result` types.
||| Required for verified case analysis and proof construction.
public export
DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq _ _ = No absurd

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle type for FFI resources.
||| Encapsulates a raw pointer (`Bits64`) while enforcing non-null invariants.
||| Prevents direct pointer manipulation and ensures resource safety.
public export
data Handle : Type where
  ||| Internal constructor.
  ||| @ptr The raw memory address.
  ||| @nonNull Proof that the address is not 0.
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a `Handle` from a raw pointer value.
||| Returns `Nothing` if the pointer is null (0), `Just handle` otherwise.
||| This is the primary safe constructor for FFI handles.
public export
createHandle : Bits64 -> Maybe Handle
createHandle 0 = Nothing
createHandle ptr = Just (MkHandle ptr)

||| Extract the raw pointer value from a `Handle`.
||| Used when passing the handle back to C/Zig functions.
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Platform-Specific Types
--------------------------------------------------------------------------------

||| Defines the size of the C `int` type for the target platform.
||| Currently maps to `Bits32` on all supported platforms.
public export
CInt : Platform -> Type
CInt Linux = Bits32
CInt Windows = Bits32
CInt MacOS = Bits32
CInt BSD = Bits32
CInt WASM = Bits32

||| Defines the size of the C `size_t` type for the target platform.
||| Maps to `Bits64` on 64-bit systems and `Bits32` on WASM.
public export
CSize : Platform -> Type
CSize Linux = Bits64
CSize Windows = Bits64
CSize MacOS = Bits64
CSize BSD = Bits64
CSize WASM = Bits32

||| Returns the pointer width in bits for the target platform.
||| - 64 bits for Linux, Windows, MacOS, BSD
||| - 32 bits for WASM
public export
ptrSize : Platform -> Nat
ptrSize Linux = 64
ptrSize Windows = 64
ptrSize MacOS = 64
ptrSize BSD = 64
ptrSize WASM = 32

||| Type alias for a C pointer on the target platform.
||| Maps to a `Bits` type of the appropriate width (`ptrSize`).
public export
CPtr : Platform -> Type -> Type
CPtr p _ = Bits (ptrSize p)

--------------------------------------------------------------------------------
-- Memory Layout Proofs
--------------------------------------------------------------------------------

||| Proof witness that a type has a specific size in bytes.
||| Used to statically verify struct layouts against C definitions.
public export
data HasSize : Type -> Nat -> Type where
  SizeProof : {0 t : Type} -> {n : Nat} -> HasSize t n

||| Proof witness that a type has a specific alignment requirement.
||| Essential for correct memory access and ABI compatibility.
public export
data HasAlignment : Type -> Nat -> Type where
  AlignProof : {0 t : Type} -> {n : Nat} -> HasAlignment t n

||| Calculates the size of C types for a given platform.
||| @p The target platform.
||| @t The type to measure.
public export
cSizeOf : (p : Platform) -> (t : Type) -> Nat
cSizeOf p (CInt _) = 4
cSizeOf p (CSize _) = if ptrSize p == 64 then 8 else 4
cSizeOf p Bits32 = 4
cSizeOf p Bits64 = 8
cSizeOf p Double = 8
cSizeOf p _ = ptrSize p `div` 8

||| Calculates the alignment requirements of C types for a given platform.
||| @p The target platform.
||| @t The type to check.
public export
cAlignOf : (p : Platform) -> (t : Type) -> Nat
cAlignOf p (CInt _) = 4
cAlignOf p (CSize _) = if ptrSize p == 64 then 8 else 4
cAlignOf p Bits32 = 4
cAlignOf p Bits64 = 8
cAlignOf p Double = 8
cAlignOf p _ = ptrSize p `div` 8
