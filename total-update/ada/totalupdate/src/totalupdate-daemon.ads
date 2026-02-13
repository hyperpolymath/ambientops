--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TotalUpdate.Daemon - Main daemon control and coordination
--  Manages update scheduling, checks, and system integration

with Ada.Calendar;

package TotalUpdate.Daemon is

   --  Daemon status information
   type Daemon_Status is record
      Is_Running         : Boolean := False;
      PID                : Natural := 0;
      Uptime             : Duration := 0.0;
      Last_Check_Time    : String (1 .. 25) := (others => ' ');
      Next_Check_Time    : String (1 .. 25) := (others => ' ');
      Pending_Updates    : Natural := 0;
      Check_Interval_Secs : Natural := 14400;  --  4 hours default
      Auto_Update        : Boolean := False;
      Snapshot_Method    : String (1 .. 20) := (others => ' ');
   end record;

   --  Start daemon in foreground (blocking)
   procedure Run_Foreground;

   --  Start daemon as background process
   procedure Run_Background;

   --  Stop the running daemon
   procedure Stop;

   --  Trigger an immediate update check
   procedure Trigger_Check;

   --  Get current daemon status
   function Get_Status return Daemon_Status;

   --  Check if daemon is running
   function Is_Running return Boolean;

   --  Signal handlers
   procedure Handle_SIGTERM;
   procedure Handle_SIGHUP;

private

   --  Internal state
   Running : Boolean := False;
   Start_Time : Ada.Calendar.Time;

end TotalUpdate.Daemon;
