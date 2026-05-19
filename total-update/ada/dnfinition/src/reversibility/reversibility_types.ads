--  SPDX-License-Identifier: PMPL-1.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Reversibility Types - Core types for transaction safety and rollback
--
--  HONESTY NOTE (2026-05-18 audit): This unit was previously marked
--  SPARK_Mode (On) and carried ghost functions
--  (Snapshot_Exists / System_State_Matches_Snapshot / ...) whose bodies
--  are stubbed to return True. No GNATprove proof has ever been run or
--  passed (the unit does not even pass SPARK Phase-2 legality: see the
--  record-component / type name clash on Rollback_Result.Snapshot_ID).
--  SPARK_Mode is therefore set Off until a genuine proof obligation
--  exists. The real reversibility obligations are tracked as proof debt
--  in PROOF-NEEDS.md (Idris2), NOT claimed as proven here.

pragma SPARK_Mode (Off);

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
      Status         : Rollback_Status := Not_Started;
      Message        : Unbounded_String;
      Target_Snapshot : Snapshot_ID := Null_Snapshot;
      --  Renamed from Snapshot_ID: a record component named identically to
      --  the type Snapshot_ID is a SPARK/Ada name clash and was one of the
      --  legality errors that blocked GNATprove Phase 2.
   end record;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Reversibility Obligations (UNPROVEN — tracked proof debt)
   --  ═══════════════════════════════════════════════════════════════════════
   --
   --  These properties are NOT formally verified. They were previously
   --  expressed as SPARK ghost functions with stub bodies (return True),
   --  which constitutes proof theatre. They are recorded here as prose
   --  obligations and tracked in PROOF-NEEDS.md for an Idris2 model:
   --
   --    O-REV-1  Snapshot_Exists: a snapshot referenced by a non-null
   --             Snapshot_ID is actually present in backend storage.
   --    O-REV-2  Snapshot_Is_Valid: a "Valid"-state snapshot is restorable.
   --    O-REV-3  System_State_Matches_Snapshot: after a Completed rollback,
   --             on-disk system state equals the snapshot's captured state
   --             (rollback atomicity / no partial state).
   --    O-REV-4  Monotonic snapshot IDs: issued IDs strictly increase and
   --             are never reused after deletion.
   --
   --  None of O-REV-1..4 are checked at compile time or runtime today.

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
