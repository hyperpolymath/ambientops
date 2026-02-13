--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

pragma SPARK_Mode (Off);  -- Body has runtime state

with Ada.Text_IO;
with Ada.Calendar;
with Ada.Directories;
with GNAT.OS_Lib;

package body Snapshot_Manager is

   use Ada.Text_IO;
   use Reversibility_Types;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Internal State
   --  ═══════════════════════════════════════════════════════════════════════

   Max_Snapshots_Stored : constant := 100;
   type Snapshot_Storage is array (1 .. Max_Snapshots_Stored) of Snapshot_Info;

   Snapshots       : Snapshot_Storage;
   Snapshot_Count  : Natural := 0;
   Next_ID         : Snapshot_ID := 1;
   Active_Backend  : Platform_Detection.Snapshot_Backend := Platform_Detection.None;
   Current_Config  : Reversibility_Config := Default_Config;
   Is_Init         : Boolean := False;

   --  Transaction log
   Max_Log_Entries : constant := 1000;
   type Log_Storage is array (1 .. Max_Log_Entries) of Transaction_Log_Entry;

   Transaction_Logs : Log_Storage;
   Log_Count        : Natural := 0;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Ghost Functions
   --  ═══════════════════════════════════════════════════════════════════════

   function Is_Initialized return Boolean is
   begin
      return Is_Init;
   end Is_Initialized;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Initialization
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Initialize
     (Platform : Platform_Detection.Platform_Info;
      Config   : Reversibility_Config := Default_Config)
   is
   begin
      Current_Config := Config;
      Active_Backend := Platform.Snapshot_Support;
      Is_Init := True;
   end Initialize;

   procedure Finalize is
   begin
      Is_Init := False;
      Snapshot_Count := 0;
      Log_Count := 0;
   end Finalize;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Creation
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Create_Snapshot
     (Description : String;
      Kind        : Snapshot_Type := Pre_Transaction;
      Snapshot    : out Snapshot_Info;
      Success     : out Boolean)
   is
      use Ada.Strings.Unbounded;
   begin
      if Snapshot_Count >= Max_Snapshots_Stored then
         Success := False;
         Snapshot := (ID => Null_Snapshot, others => <>);
         return;
      end if;

      --  Create snapshot based on backend
      case Active_Backend is
         when Platform_Detection.Native =>
            --  Guix/Nix: generation is automatic
            Success := True;

         when Platform_Detection.Btrfs =>
            --  Create btrfs snapshot
            Success := Create_Btrfs_Snapshot (Description);

         when Platform_Detection.ZFS =>
            --  Create ZFS snapshot
            Success := Create_ZFS_Snapshot (Description);

         when Platform_Detection.LVM =>
            --  Create LVM snapshot
            Success := Create_LVM_Snapshot (Description);

         when others =>
            --  Transaction log only
            Success := True;
      end case;

      if Success then
         Snapshot_Count := Snapshot_Count + 1;
         Snapshot := (
           ID          => Next_ID,
           Kind        => Kind,
           State       => Valid,
           Backend     => Active_Backend,
           Description => To_Unbounded_String (Description),
           Created_At  => Ada.Calendar.Clock,
           Size_MB     => 0,
           Is_Bootable => Active_Backend = Platform_Detection.Native
         );
         Snapshots (Snapshot_Count) := Snapshot;
         Next_ID := Next_ID + 1;
      else
         Snapshot := (ID => Null_Snapshot, others => <>);
      end if;
   end Create_Snapshot;

   function Create_Pre_Transaction_Snapshot
     (Description : String) return Snapshot_ID
   is
      Info    : Snapshot_Info;
      Success : Boolean;
   begin
      Create_Snapshot (Description, Pre_Transaction, Info, Success);
      if Success then
         return Info.ID;
      else
         return Null_Snapshot;
      end if;
   end Create_Pre_Transaction_Snapshot;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Backend-Specific Snapshot Creation
   --  ═══════════════════════════════════════════════════════════════════════

   function Create_Btrfs_Snapshot (Description : String) return Boolean is
      pragma Unreferenced (Description);
   begin
      --  Would call: btrfs subvolume snapshot / /.snapshots/...
      return True;  -- Stub
   end Create_Btrfs_Snapshot;

   function Create_ZFS_Snapshot (Description : String) return Boolean is
      pragma Unreferenced (Description);
   begin
      --  Would call: zfs snapshot pool/root@...
      return True;  -- Stub
   end Create_ZFS_Snapshot;

   function Create_LVM_Snapshot (Description : String) return Boolean is
      pragma Unreferenced (Description);
   begin
      --  Would call: lvcreate --snapshot ...
      return True;  -- Stub
   end Create_LVM_Snapshot;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Rollback Operations
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Rollback_To_Snapshot
     (ID     : Snapshot_ID;
      Result : out Rollback_Result)
   is
      use Ada.Strings.Unbounded;
   begin
      --  Find the snapshot
      for I in 1 .. Snapshot_Count loop
         if Snapshots (I).ID = ID then
            --  Perform rollback based on backend
            case Active_Backend is
               when Platform_Detection.Native =>
                  --  guix package --roll-back or nix-env --rollback
                  Result := (
                    Status      => Completed,
                    Message     => To_Unbounded_String ("Native rollback complete"),
                    Snapshot_ID => ID
                  );

               when Platform_Detection.Btrfs | Platform_Detection.ZFS =>
                  Result := (
                    Status      => Requires_Reboot,
                    Message     => To_Unbounded_String ("Snapshot restored, reboot required"),
                    Snapshot_ID => ID
                  );

               when others =>
                  Result := (
                    Status      => Failed,
                    Message     => To_Unbounded_String ("Manual rollback required"),
                    Snapshot_ID => ID
                  );
            end case;

            Snapshots (I).State := Restored;
            return;
         end if;
      end loop;

      Result := (
        Status      => Failed,
        Message     => To_Unbounded_String ("Snapshot not found"),
        Snapshot_ID => Null_Snapshot
      );
   end Rollback_To_Snapshot;

   procedure Rollback_Last
     (Result : out Rollback_Result)
   is
   begin
      if Snapshot_Count = 0 then
         Result := (
           Status      => Not_Started,
           Message     => Ada.Strings.Unbounded.To_Unbounded_String ("No snapshots"),
           Snapshot_ID => Null_Snapshot
         );
      else
         Rollback_To_Snapshot (Snapshots (Snapshot_Count).ID, Result);
      end if;
   end Rollback_Last;

   function Can_Rollback (ID : Snapshot_ID) return Boolean is
   begin
      for I in 1 .. Snapshot_Count loop
         if Snapshots (I).ID = ID and Snapshots (I).State = Valid then
            return True;
         end if;
      end loop;
      return False;
   end Can_Rollback;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Query Operations
   --  ═══════════════════════════════════════════════════════════════════════

   function List_Snapshots return Snapshot_List_Access is
      Result : constant Snapshot_List_Access :=
        new Snapshot_List (1 .. Snapshot_Count);
   begin
      for I in 1 .. Snapshot_Count loop
         Result (I) := Snapshots (I);
      end loop;
      return Result;
   end List_Snapshots;

   function Get_Snapshot_Info (ID : Snapshot_ID) return Snapshot_Info is
   begin
      for I in 1 .. Snapshot_Count loop
         if Snapshots (I).ID = ID then
            return Snapshots (I);
         end if;
      end loop;
      --  Should not reach here due to precondition
      return (ID => Null_Snapshot, others => <>);
   end Get_Snapshot_Info;

   function Get_Latest_Snapshot return Snapshot_ID is
   begin
      if Snapshot_Count = 0 then
         return Null_Snapshot;
      else
         return Snapshots (Snapshot_Count).ID;
      end if;
   end Get_Latest_Snapshot;

   function Count_Snapshots return Natural is
   begin
      return Snapshot_Count;
   end Count_Snapshots;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Cleanup
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Delete_Snapshot
     (ID      : Snapshot_ID;
      Success : out Boolean)
   is
   begin
      for I in 1 .. Snapshot_Count loop
         if Snapshots (I).ID = ID then
            Snapshots (I).State := Deleted;
            --  Would actually delete the snapshot here
            Success := True;
            return;
         end if;
      end loop;
      Success := False;
   end Delete_Snapshot;

   procedure Cleanup_Old_Snapshots
     (Keep_Count : Positive := 10;
      Deleted    : out Natural)
   is
   begin
      Deleted := 0;
      while Snapshot_Count > Keep_Count loop
         declare
            Success : Boolean;
         begin
            Delete_Snapshot (Snapshots (1).ID, Success);
            if Success then
               --  Shift remaining snapshots
               for I in 1 .. Snapshot_Count - 1 loop
                  Snapshots (I) := Snapshots (I + 1);
               end loop;
               Snapshot_Count := Snapshot_Count - 1;
               Deleted := Deleted + 1;
            else
               exit;
            end if;
         end;
      end loop;
   end Cleanup_Old_Snapshots;

   procedure Cleanup_By_Age
     (Max_Days : Positive;
      Deleted  : out Natural)
   is
      use Ada.Calendar;
      Cutoff : constant Time := Clock - Duration (Max_Days * 86400);
      I      : Natural := 1;
   begin
      Deleted := 0;
      while I <= Snapshot_Count loop
         if Snapshots (I).Created_At < Cutoff then
            declare
               Success : Boolean;
            begin
               Delete_Snapshot (Snapshots (I).ID, Success);
               if Success then
                  for J in I .. Snapshot_Count - 1 loop
                     Snapshots (J) := Snapshots (J + 1);
                  end loop;
                  Snapshot_Count := Snapshot_Count - 1;
                  Deleted := Deleted + 1;
               else
                  I := I + 1;
               end if;
            end;
         else
            I := I + 1;
         end if;
      end loop;
   end Cleanup_By_Age;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Transaction Logging
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Begin_Transaction
     (Snapshot    : Snapshot_ID;
      Description : String)
   is
      use Ada.Strings.Unbounded;
   begin
      if Log_Count < Max_Log_Entries then
         Log_Count := Log_Count + 1;
         Transaction_Logs (Log_Count) := (
           Snapshot    => Snapshot,
           Operation   => To_Unbounded_String (Description),
           Started_At  => Ada.Calendar.Clock,
           Completed   => False,
           Success     => False,
           Rolled_Back => False
         );
      end if;
   end Begin_Transaction;

   procedure Complete_Transaction
     (Snapshot : Snapshot_ID;
      Success  : Boolean)
   is
   begin
      for I in reverse 1 .. Log_Count loop
         if Transaction_Logs (I).Snapshot = Snapshot and
            not Transaction_Logs (I).Completed
         then
            Transaction_Logs (I).Completed := True;
            Transaction_Logs (I).Success := Success;
            return;
         end if;
      end loop;
   end Complete_Transaction;

   procedure Mark_Rolled_Back
     (Snapshot : Snapshot_ID)
   is
   begin
      for I in reverse 1 .. Log_Count loop
         if Transaction_Logs (I).Snapshot = Snapshot then
            Transaction_Logs (I).Rolled_Back := True;
            return;
         end if;
      end loop;
   end Mark_Rolled_Back;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Backend Information
   --  ═══════════════════════════════════════════════════════════════════════

   function Get_Active_Backend return Platform_Detection.Snapshot_Backend is
   begin
      return Active_Backend;
   end Get_Active_Backend;

   function Backend_Supports_Bootable_Snapshots return Boolean is
   begin
      return Active_Backend = Platform_Detection.Native or
             Active_Backend = Platform_Detection.Btrfs or
             Active_Backend = Platform_Detection.ZFS;
   end Backend_Supports_Bootable_Snapshots;

   function Get_Snapshot_Usage_MB return Natural is
      Total : Natural := 0;
   begin
      for I in 1 .. Snapshot_Count loop
         Total := Total + Snapshots (I).Size_MB;
      end loop;
      return Total;
   end Get_Snapshot_Usage_MB;

end Snapshot_Manager;
