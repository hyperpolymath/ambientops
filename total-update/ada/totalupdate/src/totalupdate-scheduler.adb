--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

with Ada.Calendar.Formatting;

with TotalUpdate.Logging;
with TotalUpdate.Strategy;

package body TotalUpdate.Scheduler is

   use Ada.Calendar;
   use TotalUpdate.Logging;

   procedure Do_Update_Check is
   begin
      Info ("Running scheduled update check");

      --  Ensure we have a recovery point before any operations
      if TotalUpdate.Strategy.Has_Recovery_Point then
         --  Check for updates via backends
         --  This would call into DNFinition backends
         Info ("Checking for available updates...");

         --  Log completion
         Info ("Update check completed");
      else
         Warning ("No recovery point available, skipping update check");
      end if;
   end Do_Update_Check;

   procedure Initialize (Check_Interval : Duration) is
   begin
      Interval := Check_Interval;
      Last_Check := Clock;
      Next_Check := Clock + Check_Interval;
      Initialized := True;

      Info ("Scheduler initialized (interval: " &
            Duration'Image (Check_Interval) & "s)");
   end Initialize;

   procedure Process is
      Now : constant Time := Clock;
   begin
      if not Initialized then
         return;
      end if;

      --  Check for manual trigger
      if Pending_Now then
         Pending_Now := False;
         Last_Check := Now;
         Next_Check := Now + Interval;
         Do_Update_Check;
         return;
      end if;

      --  Check if scheduled time has passed
      if not Is_Paused and then Now >= Next_Check then
         Last_Check := Now;
         Next_Check := Now + Interval;
         Do_Update_Check;
      end if;
   end Process;

   procedure Shutdown is
   begin
      Info ("Scheduler shutting down");
      Initialized := False;
   end Shutdown;

   procedure Trigger_Now is
   begin
      Info ("Manual check triggered");
      Pending_Now := True;
   end Trigger_Now;

   procedure Pause is
   begin
      Info ("Scheduler paused");
      Is_Paused := True;
   end Pause;

   procedure Resume is
   begin
      Info ("Scheduler resumed");
      Is_Paused := False;
      --  Schedule next check from now
      Next_Check := Clock + Interval;
   end Resume;

   function Get_Status return Scheduler_Status is
      Status : Scheduler_Status;
   begin
      Status.Interval_Secs := Natural (Interval);
      Status.Paused := Is_Paused;

      if Initialized then
         declare
            Last_Str : constant String :=
              Ada.Calendar.Formatting.Image (Last_Check);
            Next_Str : constant String :=
              Ada.Calendar.Formatting.Image (Next_Check);
         begin
            if Last_Str'Length <= 25 then
               Status.Last_Check_Str (1 .. Last_Str'Length) := Last_Str;
            end if;
            if Next_Str'Length <= 25 then
               Status.Next_Check_Str (1 .. Next_Str'Length) := Next_Str;
            end if;
         end;
      end if;

      return Status;
   end Get_Status;

   procedure Set_Interval (Interval_New : Duration) is
   begin
      Interval := Interval_New;
      --  Reschedule next check
      Next_Check := Clock + Interval_New;
      Info ("Check interval updated to " & Duration'Image (Interval_New) & "s");
   end Set_Interval;

end TotalUpdate.Scheduler;
