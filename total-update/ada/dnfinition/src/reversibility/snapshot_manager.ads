--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Snapshot Manager - Core reversibility layer with SPARK verification
--  This is the CRITICAL module that ensures all operations can be rolled back

pragma SPARK_Mode (On);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Platform_Detection;    use Platform_Detection;
with Reversibility_Types;   use Reversibility_Types;

package Snapshot_Manager is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Module State (for SPARK contracts)
   --  ═══════════════════════════════════════════════════════════════════════

   Initialized : Boolean := False
     with Ghost;
   --  Ghost variable tracking initialization state

   function Is_Initialized return Boolean
     with Ghost,
          Global => Initialized;

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

   function Create_Pre_Transaction_Snapshot
     (Description : String) return Snapshot_ID
     with Pre  => Is_Initialized,
          Post => (if Create_Pre_Transaction_Snapshot'Result /= Null_Snapshot
                   then Snapshot_Exists (Create_Pre_Transaction_Snapshot'Result));
   --  Convenience function: returns Null_Snapshot on failure

   --  ═══════════════════════════════════════════════════════════════════════
   --  Rollback Operations (CRITICAL - Core Safety Feature)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Rollback_To_Snapshot
     (ID     : Snapshot_ID;
      Result : out Rollback_Result)
     with Pre  => Is_Initialized and then
                  Valid_Snapshot (ID) and then
                  Snapshot_Exists (ID),
          Post => (if Result.Status = Completed then
                     System_State_Matches_Snapshot (ID))
                  or else
                  (Result.Status in Failed | Requires_Reboot);
   --  Restore system to snapshot state.
   --  On success, system state matches snapshot exactly.
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
     with Pre  => Is_Initialized,
          Post => Get_Latest_Snapshot'Result = Null_Snapshot or else
                  Snapshot_Exists (Get_Latest_Snapshot'Result);
   --  Get the most recent snapshot ID, or Null_Snapshot if none

   function Count_Snapshots return Natural
     with Pre => Is_Initialized;
   --  Count total snapshots

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Cleanup
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Delete_Snapshot
     (ID      : Snapshot_ID;
      Success : out Boolean)
     with Pre  => Is_Initialized and then Valid_Snapshot (ID),
          Post => (if Success then not Snapshot_Exists (ID));
   --  Delete a specific snapshot

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
