--  SPDX-License-Identifier: PMPL-1.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Snapshot Manager - Core reversibility layer
--  This is the CRITICAL module that ensures all operations can be rolled back
--
--  HONESTY NOTE (2026-05-18 audit): this spec was SPARK_Mode (On) while its
--  body was SPARK_Mode (Off), so GNATprove never verified ANY postcondition
--  here. The postconditions also referenced ghost functions stubbed to
--  return True (e.g. System_State_Matches_Snapshot), making the headline
--  "reversibility guarantee" vacuous even if it had been proved. SPARK_Mode
--  is now Off. The retained Pre/Post are ordinary Ada 2022 assertions
--  (runtime-checked under -gnata only), NOT formal proofs. The real
--  reversibility obligations are tracked as proof debt in PROOF-NEEDS.md.

pragma SPARK_Mode (Off);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Platform_Detection;    use Platform_Detection;
with Reversibility_Types;   use Reversibility_Types;

package Snapshot_Manager is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Module State (for SPARK contracts)
   --  ═══════════════════════════════════════════════════════════════════════

   function Is_Initialized return Boolean;
   --  True once Initialize has been called. Backed by the body's real
   --  Is_Init flag (no longer a Ghost stub).

   --  ═══════════════════════════════════════════════════════════════════════
   --  Initialization
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Initialize
     (Platform : Platform_Info;
      Config   : Reversibility_Config := Default_Config)
     with Pre  => not Is_Initialized,
          Post => Is_Initialized;
   --  Initialize the snapshot manager for the current platform

   procedure Finalize
     with Pre  => Is_Initialized,
          Post => not Is_Initialized;
   --  Clean up resources

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Creation (CRITICAL - Must Never Fail Silently)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Create_Snapshot
     (Description : String;
      Kind        : Snapshot_Type := Pre_Transaction;
      Snapshot    : out Snapshot_Info;
      Success     : out Boolean)
     with Pre  => Is_Initialized,
          Post => (if Success then
                     Valid_Snapshot (Snapshot.ID) and
                     Snapshot.State = Valid);
   --  Create a new snapshot. On failure, Success is False.
   --  NEVER proceed with package operations if snapshot creation fails.
   --  NOTE: the Post above is a runtime assertion only (SPARK_Mode Off).

   function Create_Pre_Transaction_Snapshot
     (Description : String) return Snapshot_ID
     with Pre  => Is_Initialized;
   --  Convenience function: returns Null_Snapshot on failure.
   --  Obligation O-REV-1 (result refers to a really-stored snapshot) is
   --  UNPROVEN — tracked in PROOF-NEEDS.md.

   --  ═══════════════════════════════════════════════════════════════════════
   --  Rollback Operations (CRITICAL - Core Safety Feature)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Rollback_To_Snapshot
     (ID     : Snapshot_ID;
      Result : out Rollback_Result)
     with Pre  => Is_Initialized and then
                  Valid_Snapshot (ID);
   --  Restore system to snapshot state.
   --  CRITICAL UNPROVEN OBLIGATION O-REV-3: "on Completed, on-disk system
   --  state matches the snapshot exactly (rollback atomicity, no partial
   --  state)" is NOT verified. The previous Post asserting this was vacuous
   --  (System_State_Matches_Snapshot was a `return True` stub). Tracked in
   --  PROOF-NEEDS.md.
   --  May require reboot for immutable systems.

   procedure Rollback_Last
     (Result : out Rollback_Result)
     with Pre  => Is_Initialized,
          Post => Result.Status in Completed | Failed | Requires_Reboot |
                  Not_Started;
   --  Rollback to the most recent snapshot

   function Can_Rollback (ID : Snapshot_ID) return Boolean
     with Pre => Is_Initialized;
   --  Check if rollback is possible for a given snapshot

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Query Operations
   --  ═══════════════════════════════════════════════════════════════════════

   function List_Snapshots return Snapshot_List_Access
     with Pre => Is_Initialized;
   --  Get all available snapshots

   function Get_Snapshot_Info (ID : Snapshot_ID) return Snapshot_Info
     with Pre => Is_Initialized and then Valid_Snapshot (ID);
   --  Get detailed info about a specific snapshot

   function Get_Latest_Snapshot return Snapshot_ID
     with Pre  => Is_Initialized;
   --  Get the most recent snapshot ID, or Null_Snapshot if none.
   --  Obligation O-REV-1 (result is a really-stored snapshot) UNPROVEN.

   function Count_Snapshots return Natural
     with Pre => Is_Initialized;
   --  Count total snapshots

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Cleanup
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Delete_Snapshot
     (ID      : Snapshot_ID;
      Success : out Boolean)
     with Pre  => Is_Initialized and then Valid_Snapshot (ID);
   --  Delete a specific snapshot.
   --  Obligation (on Success the snapshot is truly gone) UNPROVEN.

   procedure Cleanup_Old_Snapshots
     (Keep_Count : Positive := 10;
      Deleted    : out Natural)
     with Pre  => Is_Initialized,
          Post => Count_Snapshots <= Keep_Count + Deleted'Old - Deleted;
   --  Remove oldest snapshots beyond Keep_Count

   procedure Cleanup_By_Age
     (Max_Days : Positive;
      Deleted  : out Natural)
     with Pre => Is_Initialized;
   --  Remove snapshots older than Max_Days

   --  ═══════════════════════════════════════════════════════════════════════
   --  Transaction Logging
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Begin_Transaction
     (Snapshot    : Snapshot_ID;
      Description : String)
     with Pre => Is_Initialized;
   --  Log start of a transaction

   procedure Complete_Transaction
     (Snapshot : Snapshot_ID;
      Success  : Boolean)
     with Pre => Is_Initialized;
   --  Log completion of a transaction

   procedure Mark_Rolled_Back
     (Snapshot : Snapshot_ID)
     with Pre => Is_Initialized;
   --  Mark a transaction as rolled back

   --  ═══════════════════════════════════════════════════════════════════════
   --  Backend Information
   --  ═══════════════════════════════════════════════════════════════════════

   function Get_Active_Backend return Snapshot_Backend
     with Pre => Is_Initialized;
   --  Which snapshot backend is being used

   function Backend_Supports_Bootable_Snapshots return Boolean
     with Pre => Is_Initialized;
   --  Can we create bootable snapshots?

   function Get_Snapshot_Usage_MB return Natural
     with Pre => Is_Initialized;
   --  Total disk space used by snapshots

end Snapshot_Manager;
