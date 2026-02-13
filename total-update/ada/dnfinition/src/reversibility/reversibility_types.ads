--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Reversibility Types - Core types for transaction safety and rollback
--  This module uses SPARK for formal verification of reversibility guarantees

pragma SPARK_Mode (On);

with Ada.Calendar;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Platform_Detection;    use Platform_Detection;

package Reversibility_Types is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Identification
   --  ═══════════════════════════════════════════════════════════════════════

   type Snapshot_ID is new Natural;
   --  Unique identifier for a snapshot. 0 means no snapshot.

   Null_Snapshot : constant Snapshot_ID := 0;

   function Valid_Snapshot (ID : Snapshot_ID) return Boolean is
     (ID > 0);

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Types
   --  ═══════════════════════════════════════════════════════════════════════

   type Snapshot_Type is
     (Pre_Transaction,    --  Before a package operation
      Pre_Upgrade,        --  Before system upgrade
      Manual,             --  User-requested snapshot
      Scheduled,          --  Automatic scheduled snapshot
      Boot_Snapshot);     --  Snapshot of last known good boot

   type Snapshot_State is
     (Valid,              --  Can be restored
      Restoring,          --  Currently being restored
      Restored,           --  Was successfully restored
      Corrupted,          --  Data integrity issue
      Deleted);           --  Marked for cleanup

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Information
   --  ═══════════════════════════════════════════════════════════════════════

   type Snapshot_Info is record
      ID          : Snapshot_ID := Null_Snapshot;
      Kind        : Snapshot_Type := Manual;
      State       : Snapshot_State := Valid;
      Backend     : Snapshot_Backend := None;
      Description : Unbounded_String;
      Created_At  : Ada.Calendar.Time;
      Size_MB     : Natural := 0;
      Is_Bootable : Boolean := False;  --  Can boot into this snapshot
   end record;

   type Snapshot_List is array (Positive range <>) of Snapshot_Info;
   type Snapshot_List_Access is access all Snapshot_List;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Transaction Logging
   --  ═══════════════════════════════════════════════════════════════════════

   type Transaction_Log_Entry is record
      Snapshot    : Snapshot_ID;
      Operation   : Unbounded_String;  --  "install vim", "upgrade", etc.
      Started_At  : Ada.Calendar.Time;
      Completed   : Boolean := False;
      Success     : Boolean := False;
      Rolled_Back : Boolean := False;
   end record;

   type Transaction_Log is array (Positive range <>) of Transaction_Log_Entry;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Rollback Status
   --  ═══════════════════════════════════════════════════════════════════════

   type Rollback_Status is
     (Not_Started,
      In_Progress,
      Completed,
      Failed,
      Requires_Reboot);

   type Rollback_Result is record
      Status      : Rollback_Status := Not_Started;
      Message     : Unbounded_String;
      Snapshot_ID : Snapshot_ID := Null_Snapshot;
   end record;

   --  ═══════════════════════════════════════════════════════════════════════
   --  SPARK Contracts for Reversibility Guarantees
   --  ═══════════════════════════════════════════════════════════════════════

   --  Ghost functions for formal verification
   function Snapshot_Exists (ID : Snapshot_ID) return Boolean
     with Ghost;
   --  True if snapshot with given ID exists in the system

   function Snapshot_Is_Valid (ID : Snapshot_ID) return Boolean
     with Ghost,
          Post => (if Snapshot_Is_Valid'Result then Snapshot_Exists (ID));
   --  True if snapshot exists and is in Valid state

   function System_State_Matches_Snapshot (ID : Snapshot_ID) return Boolean
     with Ghost,
          Pre => Snapshot_Exists (ID);
   --  True if current system state matches the snapshot

   function Current_System_State_ID return Snapshot_ID
     with Ghost;
   --  Conceptual ID of current system state (for verification)

   --  ═══════════════════════════════════════════════════════════════════════
   --  Configuration
   --  ═══════════════════════════════════════════════════════════════════════

   type Reversibility_Config is record
      Auto_Snapshot_Before_Install : Boolean := True;
      Auto_Snapshot_Before_Upgrade : Boolean := True;
      Max_Snapshots                : Positive := 10;
      Auto_Cleanup                 : Boolean := True;
      Snapshot_Path                : Unbounded_String;
      Transaction_Log_Path         : Unbounded_String;
   end record;

   Default_Config : constant Reversibility_Config :=
     (Auto_Snapshot_Before_Install => True,
      Auto_Snapshot_Before_Upgrade => True,
      Max_Snapshots                => 10,
      Auto_Cleanup                 => True,
      Snapshot_Path                => To_Unbounded_String ("/.snapshots"),
      Transaction_Log_Path         =>
        To_Unbounded_String ("/var/lib/dnfinition/transactions.log"));

end Reversibility_Types;
