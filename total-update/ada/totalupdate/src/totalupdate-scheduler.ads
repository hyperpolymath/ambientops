--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TotalUpdate.Scheduler - Update scheduling and timing
--  Manages periodic update checks and cleanup tasks

with Ada.Calendar;

package TotalUpdate.Scheduler is

   type Scheduler_Status is record
      Interval_Secs   : Natural := 14400;
      Last_Check_Str  : String (1 .. 25) := (others => ' ');
      Next_Check_Str  : String (1 .. 25) := (others => ' ');
      Paused          : Boolean := False;
   end record;

   --  Initialize scheduler with check interval
   procedure Initialize (Check_Interval : Duration);

   --  Process pending scheduled tasks (called from main loop)
   procedure Process;

   --  Shutdown scheduler
   procedure Shutdown;

   --  Trigger immediate check
   procedure Trigger_Now;

   --  Pause scheduled checks
   procedure Pause;

   --  Resume scheduled checks
   procedure Resume;

   --  Get current status
   function Get_Status return Scheduler_Status;

   --  Set check interval
   procedure Set_Interval (Interval : Duration);

private

   --  Internal state
   Initialized  : Boolean := False;
   Interval     : Duration := 14400.0;
   Last_Check   : Ada.Calendar.Time;
   Next_Check   : Ada.Calendar.Time;
   Is_Paused    : Boolean := False;
   Pending_Now  : Boolean := False;

end TotalUpdate.Scheduler;
