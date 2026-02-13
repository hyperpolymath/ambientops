--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Safety_Boundary - CRITICAL module enforcing reversibility invariants
--
--  ╔═══════════════════════════════════════════════════════════════════════════╗
--  ║  SAFETY INVARIANT (formally verified):                                    ║
--  ║                                                                           ║
--  ║  "Every modifying package operation MUST be preceded by a valid          ║
--  ║   recovery point. Operations without recovery points are REJECTED."      ║
--  ║                                                                           ║
--  ║  This invariant ensures the system can ALWAYS roll back to a known-good  ║
--  ║  state, preventing unrecoverable system corruption.                      ║
--  ╚═══════════════════════════════════════════════════════════════════════════╝
--
--  This module provides:
--  1. SPARK contracts proving the invariant holds
--  2. Runtime enforcement as a defense-in-depth layer
--  3. Safe wrappers for all modifying operations

pragma SPARK_Mode (On);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Backend_Interface;     use Backend_Interface;
with Reversibility_Types;   use Reversibility_Types;

package Safety_Boundary is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Recovery Point Token (proof of recovery point creation)
   --  ═══════════════════════════════════════════════════════════════════════

   --  A Recovery_Point_Token represents proof that a recovery point exists.
   --  Modifying operations REQUIRE this token, enforcing the invariant at
   --  the type system level.

   type Recovery_Point_Token is private;
   Null_Token : constant Recovery_Point_Token;

   function Is_Valid (Token : Recovery_Point_Token) return Boolean
     with Ghost;
   --  Ghost function: True if token represents a valid recovery point

   function Token_Snapshot_ID (Token : Recovery_Point_Token) return Snapshot_ID
     with Pre => Is_Valid (Token);
   --  Get the snapshot ID associated with this token

   --  ═══════════════════════════════════════════════════════════════════════
   --  Recovery Point Creation (the ONLY way to get a valid token)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Create_Recovery_Point
     (Description : String;
      Token       : out Recovery_Point_Token;
      Success     : out Boolean)
     with Post => (if Success then Is_Valid (Token)
                   else Token = Null_Token);
   --  Create a recovery point before any modifying operation.
   --  Returns a valid token on success, Null_Token on failure.
   --
   --  CRITICAL: This is the ONLY way to obtain a valid Recovery_Point_Token.
   --  All modifying operations require this token.

   function Try_Create_Recovery_Point
     (Description : String) return Recovery_Point_Token
     with Post => Try_Create_Recovery_Point'Result = Null_Token or else
                  Is_Valid (Try_Create_Recovery_Point'Result);
   --  Convenience function: returns Null_Token on failure

   --  ═══════════════════════════════════════════════════════════════════════
   --  THE CRITICAL INVARIANT: Safe Modifying Operations
   --  ═══════════════════════════════════════════════════════════════════════

   --  These operations REQUIRE a valid Recovery_Point_Token.
   --  The precondition enforces the invariant at compile-time via SPARK.
   --  Runtime checks provide defense-in-depth.

   function Safe_Install
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Token       : Recovery_Point_Token) return Operation_Result
     with Pre => Is_Valid (Token);
   --  Install packages with guaranteed recovery point

   function Safe_Remove
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Purge       : Boolean;
      Token       : Recovery_Point_Token) return Operation_Result
     with Pre => Is_Valid (Token);
   --  Remove packages with guaranteed recovery point

   function Safe_Upgrade
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Token       : Recovery_Point_Token) return Operation_Result
     with Pre => Is_Valid (Token);
   --  Upgrade packages with guaranteed recovery point

   function Safe_Upgrade_System
     (Backend : in Out Package_Manager_Backend'Class;
      Token   : Recovery_Point_Token) return Operation_Result
     with Pre => Is_Valid (Token);
   --  Upgrade entire system with guaranteed recovery point

   --  ═══════════════════════════════════════════════════════════════════════
   --  Rollback Operations (do NOT require token - they ARE the recovery)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Rollback_To_Token
     (Token  : Recovery_Point_Token;
      Result : out Rollback_Result)
     with Pre  => Is_Valid (Token),
          Post => Result.Status in Completed | Failed | Requires_Reboot;
   --  Rollback to the state captured by this token

   procedure Rollback_Last
     (Result : out Rollback_Result)
     with Post => Result.Status in Completed | Failed | Requires_Reboot | Not_Started;
   --  Rollback to the most recent recovery point

   --  ═══════════════════════════════════════════════════════════════════════
   --  Convenience: All-in-One Safe Operations
   --  ═══════════════════════════════════════════════════════════════════════

   --  These combine recovery point creation + operation + logging.
   --  They handle all safety concerns internally.

   type Safe_Operation_Result is record
      Op_Result     : Operation_Result;
      Recovery_ID   : Snapshot_ID := Null_Snapshot;
      Can_Rollback  : Boolean := False;
   end record;

   function Install_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Description : String := "Pre-install recovery point")
     return Safe_Operation_Result
     with Post => (if Install_With_Recovery'Result.Op_Result.Status = Success
                   then Install_With_Recovery'Result.Can_Rollback);
   --  Install with automatic recovery point creation

   function Remove_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Purge       : Boolean := False;
      Description : String := "Pre-remove recovery point")
     return Safe_Operation_Result
     with Post => (if Remove_With_Recovery'Result.Op_Result.Status = Success
                   then Remove_With_Recovery'Result.Can_Rollback);
   --  Remove with automatic recovery point creation

   function Upgrade_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Description : String := "Pre-upgrade recovery point")
     return Safe_Operation_Result
     with Post => (if Upgrade_With_Recovery'Result.Op_Result.Status = Success
                   then Upgrade_With_Recovery'Result.Can_Rollback);
   --  Upgrade with automatic recovery point creation

   function System_Upgrade_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Description : String := "Pre-system-upgrade recovery point")
     return Safe_Operation_Result
     with Post => (if System_Upgrade_With_Recovery'Result.Op_Result.Status = Success
                   then System_Upgrade_With_Recovery'Result.Can_Rollback);
   --  System upgrade with automatic recovery point creation

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant Verification (for testing and monitoring)
   --  ═══════════════════════════════════════════════════════════════════════

   type Invariant_Status is
     (Invariant_Holds,      --  All is well
      No_Recovery_Points,   --  System has no recovery points (first use)
      Orphaned_Operation,   --  Found operation without recovery point
      Corrupted_State);     --  Recovery point data inconsistent

   function Check_Invariant return Invariant_Status;
   --  Verify the safety invariant holds

   function Last_Recovery_Point return Snapshot_ID;
   --  Get the most recent recovery point ID

   function Recovery_Point_Count return Natural;
   --  Count available recovery points

   --  ═══════════════════════════════════════════════════════════════════════
   --  Emergency Operations (use with extreme caution)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Force_Operation_Without_Recovery
     (Acknowledged : Boolean)
     with Pre => Acknowledged;
   --  DANGER: Allow next operation without recovery point.
   --  Only use in extreme circumstances (e.g., disk full, cannot create snapshot).
   --  The Acknowledged parameter forces explicit acknowledgment of the risk.

   function Emergency_Mode_Active return Boolean;
   --  True if emergency mode was activated

   procedure Clear_Emergency_Mode;
   --  Reset to normal safe mode

private

   --  Recovery point token contains proof of recovery point existence
   type Recovery_Point_Token is record
      Snapshot   : Snapshot_ID := Null_Snapshot;
      Created_At : Unbounded_String;
      Is_Valid   : Boolean := False;
   end record;

   Null_Token : constant Recovery_Point_Token :=
     (Snapshot   => Null_Snapshot,
      Created_At => To_Unbounded_String (""),
      Is_Valid   => False);

   function Is_Valid (Token : Recovery_Point_Token) return Boolean is
     (Token.Is_Valid and then Valid_Snapshot (Token.Snapshot));

   function Token_Snapshot_ID (Token : Recovery_Point_Token) return Snapshot_ID is
     (Token.Snapshot);

   --  Module state
   Emergency_Bypass : Boolean := False;

end Safety_Boundary;
