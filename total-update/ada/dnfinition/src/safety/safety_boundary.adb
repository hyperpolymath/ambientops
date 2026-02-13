--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Safety_Boundary - Implementation of safety invariant enforcement

pragma SPARK_Mode (Off);  --  Implementation uses Snapshot_Manager

with Ada.Calendar;
with Ada.Calendar.Formatting;
with Snapshot_Manager;

package body Safety_Boundary is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Recovery Point Creation
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Create_Recovery_Point
     (Description : String;
      Token       : out Recovery_Point_Token;
      Success     : out Boolean)
   is
      Snap_Info : Reversibility_Types.Snapshot_Info;
   begin
      Token := Null_Token;
      Success := False;

      --  Attempt to create snapshot via Snapshot_Manager
      Snapshot_Manager.Create_Snapshot
        (Description => Description,
         Kind        => Pre_Transaction,
         Snapshot    => Snap_Info,
         Success     => Success);

      if Success then
         Token :=
           (Snapshot   => Snap_Info.ID,
            Created_At => To_Unbounded_String
              (Ada.Calendar.Formatting.Image (Ada.Calendar.Clock)),
            Is_Valid   => True);
      end if;
   end Create_Recovery_Point;

   function Try_Create_Recovery_Point
     (Description : String) return Recovery_Point_Token
   is
      Token   : Recovery_Point_Token;
      Success : Boolean;
   begin
      Create_Recovery_Point (Description, Token, Success);
      return Token;
   end Try_Create_Recovery_Point;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Safe Modifying Operations
   --  ═══════════════════════════════════════════════════════════════════════

   function Safe_Install
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Token       : Recovery_Point_Token) return Operation_Result
   is
      Result : Operation_Result;
   begin
      --  Runtime defense-in-depth check (SPARK pre-condition provides static check)
      if not Is_Valid (Token) and not Emergency_Bypass then
         Result.Status := Failed;
         Result.Message := To_Unbounded_String
           ("SAFETY VIOLATION: Install requires valid recovery point");
         return Result;
      end if;

      --  Log the operation
      Snapshot_Manager.Begin_Transaction
        (Token.Snapshot, "install");

      --  Perform the actual install
      Result := Backend.Install (Packages, Natural (Token.Snapshot));

      --  Log completion
      Snapshot_Manager.Complete_Transaction
        (Token.Snapshot, Result.Status = Success);

      --  Reset emergency mode after operation
      Emergency_Bypass := False;

      return Result;
   end Safe_Install;

   function Safe_Remove
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Purge       : Boolean;
      Token       : Recovery_Point_Token) return Operation_Result
   is
      Result : Operation_Result;
   begin
      if not Is_Valid (Token) and not Emergency_Bypass then
         Result.Status := Failed;
         Result.Message := To_Unbounded_String
           ("SAFETY VIOLATION: Remove requires valid recovery point");
         return Result;
      end if;

      Snapshot_Manager.Begin_Transaction (Token.Snapshot, "remove");
      Result := Backend.Remove (Packages, Purge, Natural (Token.Snapshot));
      Snapshot_Manager.Complete_Transaction
        (Token.Snapshot, Result.Status = Success);
      Emergency_Bypass := False;

      return Result;
   end Safe_Remove;

   function Safe_Upgrade
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Token       : Recovery_Point_Token) return Operation_Result
   is
      Result : Operation_Result;
   begin
      if not Is_Valid (Token) and not Emergency_Bypass then
         Result.Status := Failed;
         Result.Message := To_Unbounded_String
           ("SAFETY VIOLATION: Upgrade requires valid recovery point");
         return Result;
      end if;

      Snapshot_Manager.Begin_Transaction (Token.Snapshot, "upgrade");
      Result := Backend.Upgrade (Packages, Natural (Token.Snapshot));
      Snapshot_Manager.Complete_Transaction
        (Token.Snapshot, Result.Status = Success);
      Emergency_Bypass := False;

      return Result;
   end Safe_Upgrade;

   function Safe_Upgrade_System
     (Backend : in Out Package_Manager_Backend'Class;
      Token   : Recovery_Point_Token) return Operation_Result
   is
      Result : Operation_Result;
   begin
      if not Is_Valid (Token) and not Emergency_Bypass then
         Result.Status := Failed;
         Result.Message := To_Unbounded_String
           ("SAFETY VIOLATION: System upgrade requires valid recovery point");
         return Result;
      end if;

      Snapshot_Manager.Begin_Transaction (Token.Snapshot, "system-upgrade");
      Result := Backend.Upgrade_System (Natural (Token.Snapshot));
      Snapshot_Manager.Complete_Transaction
        (Token.Snapshot, Result.Status = Success);
      Emergency_Bypass := False;

      return Result;
   end Safe_Upgrade_System;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Rollback Operations
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Rollback_To_Token
     (Token  : Recovery_Point_Token;
      Result : out Rollback_Result)
   is
   begin
      if not Is_Valid (Token) then
         Result.Status := Failed;
         Result.Message := To_Unbounded_String ("Invalid recovery token");
         return;
      end if;

      Snapshot_Manager.Rollback_To_Snapshot (Token.Snapshot, Result);

      if Result.Status = Completed then
         Snapshot_Manager.Mark_Rolled_Back (Token.Snapshot);
      end if;
   end Rollback_To_Token;

   procedure Rollback_Last
     (Result : out Rollback_Result)
   is
   begin
      Snapshot_Manager.Rollback_Last (Result);
   end Rollback_Last;

   --  ═══════════════════════════════════════════════════════════════════════
   --  All-in-One Safe Operations
   --  ═══════════════════════════════════════════════════════════════════════

   function Install_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Description : String := "Pre-install recovery point")
     return Safe_Operation_Result
   is
      Result  : Safe_Operation_Result;
      Token   : Recovery_Point_Token;
      Success : Boolean;
   begin
      --  Step 1: Create recovery point
      Create_Recovery_Point (Description, Token, Success);

      if not Success then
         Result.Op_Result.Status := Failed;
         Result.Op_Result.Message := To_Unbounded_String
           ("Failed to create recovery point - operation aborted");
         Result.Can_Rollback := False;
         return Result;
      end if;

      Result.Recovery_ID := Token.Snapshot;

      --  Step 2: Perform the operation with safety guarantee
      Result.Op_Result := Safe_Install (Backend, Packages, Token);
      Result.Can_Rollback := True;

      return Result;
   end Install_With_Recovery;

   function Remove_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Purge       : Boolean := False;
      Description : String := "Pre-remove recovery point")
     return Safe_Operation_Result
   is
      Result  : Safe_Operation_Result;
      Token   : Recovery_Point_Token;
      Success : Boolean;
   begin
      Create_Recovery_Point (Description, Token, Success);

      if not Success then
         Result.Op_Result.Status := Failed;
         Result.Op_Result.Message := To_Unbounded_String
           ("Failed to create recovery point - operation aborted");
         Result.Can_Rollback := False;
         return Result;
      end if;

      Result.Recovery_ID := Token.Snapshot;
      Result.Op_Result := Safe_Remove (Backend, Packages, Purge, Token);
      Result.Can_Rollback := True;

      return Result;
   end Remove_With_Recovery;

   function Upgrade_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Packages    : Package_List;
      Description : String := "Pre-upgrade recovery point")
     return Safe_Operation_Result
   is
      Result  : Safe_Operation_Result;
      Token   : Recovery_Point_Token;
      Success : Boolean;
   begin
      Create_Recovery_Point (Description, Token, Success);

      if not Success then
         Result.Op_Result.Status := Failed;
         Result.Op_Result.Message := To_Unbounded_String
           ("Failed to create recovery point - operation aborted");
         Result.Can_Rollback := False;
         return Result;
      end if;

      Result.Recovery_ID := Token.Snapshot;
      Result.Op_Result := Safe_Upgrade (Backend, Packages, Token);
      Result.Can_Rollback := True;

      return Result;
   end Upgrade_With_Recovery;

   function System_Upgrade_With_Recovery
     (Backend     : in Out Package_Manager_Backend'Class;
      Description : String := "Pre-system-upgrade recovery point")
     return Safe_Operation_Result
   is
      Result  : Safe_Operation_Result;
      Token   : Recovery_Point_Token;
      Success : Boolean;
   begin
      Create_Recovery_Point (Description, Token, Success);

      if not Success then
         Result.Op_Result.Status := Failed;
         Result.Op_Result.Message := To_Unbounded_String
           ("Failed to create recovery point - operation aborted");
         Result.Can_Rollback := False;
         return Result;
      end if;

      Result.Recovery_ID := Token.Snapshot;
      Result.Op_Result := Safe_Upgrade_System (Backend, Token);
      Result.Can_Rollback := True;

      return Result;
   end System_Upgrade_With_Recovery;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant Verification
   --  ═══════════════════════════════════════════════════════════════════════

   function Check_Invariant return Invariant_Status is
      Count : Natural;
   begin
      Count := Snapshot_Manager.Count_Snapshots;

      if Count = 0 then
         return No_Recovery_Points;
      end if;

      --  Additional checks would verify transaction log consistency
      --  For walking skeleton, assume invariant holds if we have snapshots
      return Invariant_Holds;
   end Check_Invariant;

   function Last_Recovery_Point return Snapshot_ID is
   begin
      return Snapshot_Manager.Get_Latest_Snapshot;
   end Last_Recovery_Point;

   function Recovery_Point_Count return Natural is
   begin
      return Snapshot_Manager.Count_Snapshots;
   end Recovery_Point_Count;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Emergency Operations
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Force_Operation_Without_Recovery
     (Acknowledged : Boolean)
   is
   begin
      if Acknowledged then
         Emergency_Bypass := True;
      end if;
   end Force_Operation_Without_Recovery;

   function Emergency_Mode_Active return Boolean is
   begin
      return Emergency_Bypass;
   end Emergency_Mode_Active;

   procedure Clear_Emergency_Mode is
   begin
      Emergency_Bypass := False;
   end Clear_Emergency_Mode;

end Safety_Boundary;
