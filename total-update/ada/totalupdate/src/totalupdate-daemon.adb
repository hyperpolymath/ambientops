--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

with Ada.Text_IO;
with Ada.Calendar.Formatting;
with GNAT.OS_Lib;

with TotalUpdate.Config;
with TotalUpdate.Logging;
with TotalUpdate.Scheduler;
with TotalUpdate.Watcher;
with TotalUpdate.Strategy;

package body TotalUpdate.Daemon is

   use Ada.Text_IO;
   use TotalUpdate.Logging;

   --  PID file path
   PID_File : constant String := "/var/run/totalupdate.pid";

   procedure Initialize is
   begin
      Info ("Initializing daemon subsystems...");

      --  Initialize scheduler
      TotalUpdate.Scheduler.Initialize
        (Check_Interval => TotalUpdate.Config.Get_Check_Interval);

      --  Initialize file watcher
      TotalUpdate.Watcher.Initialize;

      --  Initialize strategy engine
      TotalUpdate.Strategy.Initialize;

      Info ("All subsystems initialized");
   end Initialize;

   procedure Cleanup is
   begin
      Info ("Shutting down daemon subsystems...");
      TotalUpdate.Scheduler.Shutdown;
      TotalUpdate.Watcher.Shutdown;
      TotalUpdate.Strategy.Shutdown;

      --  Remove PID file
      if GNAT.OS_Lib.Is_Regular_File (PID_File) then
         GNAT.OS_Lib.Delete_File (PID_File, Success => null);
      end if;

      Info ("Daemon shutdown complete");
   end Cleanup;

   procedure Write_PID_File is
      F : File_Type;
   begin
      Create (F, Out_File, PID_File);
      Put_Line (F, Natural'Image (GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id)));
      Close (F);
   exception
      when others =>
         Warning ("Could not write PID file: " & PID_File);
   end Write_PID_File;

   procedure Main_Loop is
   begin
      while Running loop
         --  Check for scheduled tasks
         TotalUpdate.Scheduler.Process;

         --  Check for filesystem changes
         TotalUpdate.Watcher.Process;

         --  Small delay to prevent busy-waiting
         delay 1.0;
      end loop;
   end Main_Loop;

   procedure Run_Foreground is
   begin
      Start_Time := Ada.Calendar.Clock;
      Running := True;

      Info ("Starting in foreground mode");
      Initialize;

      --  Write PID file even in foreground mode
      Write_PID_File;

      --  Enter main loop
      Main_Loop;

      --  Cleanup on exit
      Cleanup;
   end Run_Foreground;

   procedure Run_Background is
   begin
      --  Fork to background
      --  Note: Actual daemonization would use POSIX fork()
      --  For now, we just run in foreground with a note
      Info ("Background mode requested (running as foreground for now)");
      Run_Foreground;
   end Run_Background;

   procedure Stop is
   begin
      Info ("Stop requested");
      Running := False;
   end Stop;

   procedure Trigger_Check is
   begin
      Info ("Manual check triggered");
      TotalUpdate.Scheduler.Trigger_Now;
   end Trigger_Check;

   function Get_Status return Daemon_Status is
      Status : Daemon_Status;
      Now    : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      Status.Is_Running := Running;

      if Running then
         Status.PID := GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id);
         Status.Uptime := Now - Start_Time;
      end if;

      --  Get scheduler info
      declare
         Sched_Status : constant TotalUpdate.Scheduler.Scheduler_Status :=
           TotalUpdate.Scheduler.Get_Status;
      begin
         Status.Check_Interval_Secs := Sched_Status.Interval_Secs;
         Status.Last_Check_Time := Sched_Status.Last_Check_Str;
         Status.Next_Check_Time := Sched_Status.Next_Check_Str;
      end;

      --  Get config info
      Status.Auto_Update := TotalUpdate.Config.Get_Auto_Update;

      --  Get strategy info
      declare
         Strat_Name : constant String := TotalUpdate.Strategy.Current_Strategy_Name;
      begin
         if Strat_Name'Length <= 20 then
            Status.Snapshot_Method (1 .. Strat_Name'Length) := Strat_Name;
         else
            Status.Snapshot_Method := Strat_Name (1 .. 20);
         end if;
      end;

      return Status;
   end Get_Status;

   function Is_Running return Boolean is
   begin
      return Running;
   end Is_Running;

   procedure Handle_SIGTERM is
   begin
      Info ("Received SIGTERM, initiating shutdown");
      Stop;
   end Handle_SIGTERM;

   procedure Handle_SIGHUP is
   begin
      Info ("Received SIGHUP, reloading configuration");
      TotalUpdate.Config.Reload;
   end Handle_SIGHUP;

end TotalUpdate.Daemon;
