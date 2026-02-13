--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TotalUpdate - Universal Package Update Daemon
--  Main entry point for the Ada-based daemon component

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Calendar;
with Ada.Strings.Unbounded;

with TotalUpdate.Daemon;
with TotalUpdate.Config;
with TotalUpdate.Logging;

procedure TotalUpdate_Main is
   use Ada.Text_IO;
   use Ada.Command_Line;
   use Ada.Strings.Unbounded;

   Version : constant String := "0.1.0";

   --  Command line options
   type Run_Mode is (Mode_Daemon, Mode_Check, Mode_Status, Mode_Help, Mode_Version);

   Selected_Mode : Run_Mode := Mode_Daemon;
   Config_Path   : Unbounded_String := Null_Unbounded_String;
   Foreground    : Boolean := False;

   procedure Print_Banner is
   begin
      Put_Line ("╔═══════════════════════════════════════════════════════════╗");
      Put_Line ("║  TotalUpdate " & Version & " - Universal Package Daemon        ║");
      Put_Line ("║  Safe, Scheduled, Automatic Updates                       ║");
      Put_Line ("╚═══════════════════════════════════════════════════════════╝");
      New_Line;
   end Print_Banner;

   procedure Print_Usage is
   begin
      Print_Banner;
      Put_Line ("Usage: totalupdate [OPTIONS] [COMMAND]");
      New_Line;
      Put_Line ("Commands:");
      Put_Line ("  (none)          Start daemon (default)");
      Put_Line ("  check           Run immediate update check");
      Put_Line ("  status          Show daemon status");
      Put_Line ("  --help, -h      Show this help");
      Put_Line ("  --version, -v   Show version");
      New_Line;
      Put_Line ("Options:");
      Put_Line ("  -f, --foreground   Run in foreground (don't daemonize)");
      Put_Line ("  -c, --config PATH  Use alternate config file");
      New_Line;
      Put_Line ("Configuration:");
      Put_Line ("  Default config: ~/.config/totalupdate/config.scm");
      Put_Line ("  System config:  /etc/totalupdate/config.scm");
      New_Line;
      Put_Line ("Safety Features:");
      Put_Line ("  - Automatic snapshots before every operation");
      Put_Line ("  - Instant rollback via Guix/Nix generations");
      Put_Line ("  - Btrfs/ZFS snapshot fallback on other systems");
      Put_Line ("  - Transaction logging for audit trail");
   end Print_Usage;

   procedure Parse_Arguments is
      I : Positive := 1;
   begin
      while I <= Argument_Count loop
         declare
            Arg : constant String := Argument (I);
         begin
            if Arg = "--help" or else Arg = "-h" then
               Selected_Mode := Mode_Help;
               return;

            elsif Arg = "--version" or else Arg = "-v" then
               Selected_Mode := Mode_Version;
               return;

            elsif Arg = "-f" or else Arg = "--foreground" then
               Foreground := True;

            elsif Arg = "-c" or else Arg = "--config" then
               if I < Argument_Count then
                  I := I + 1;
                  Config_Path := To_Unbounded_String (Argument (I));
               else
                  Put_Line (Standard_Error, "Error: --config requires a path");
                  Set_Exit_Status (Failure);
                  return;
               end if;

            elsif Arg = "check" then
               Selected_Mode := Mode_Check;

            elsif Arg = "status" then
               Selected_Mode := Mode_Status;

            elsif Arg (Arg'First) = '-' then
               Put_Line (Standard_Error, "Unknown option: " & Arg);
               Put_Line (Standard_Error, "Use --help for usage");
               Set_Exit_Status (Failure);
               return;

            else
               Put_Line (Standard_Error, "Unknown command: " & Arg);
               Put_Line (Standard_Error, "Use --help for usage");
               Set_Exit_Status (Failure);
               return;
            end if;
         end;
         I := I + 1;
      end loop;
   end Parse_Arguments;

   procedure Run_Daemon is
   begin
      TotalUpdate.Logging.Info ("Starting TotalUpdate daemon v" & Version);

      --  Load configuration
      if Config_Path /= Null_Unbounded_String then
         TotalUpdate.Config.Load (To_String (Config_Path));
      else
         TotalUpdate.Config.Load_Default;
      end if;

      --  Start daemon
      if Foreground then
         TotalUpdate.Logging.Info ("Running in foreground mode");
         TotalUpdate.Daemon.Run_Foreground;
      else
         TotalUpdate.Logging.Info ("Daemonizing...");
         TotalUpdate.Daemon.Run_Background;
      end if;
   end Run_Daemon;

   procedure Run_Check is
   begin
      Put_Line ("Triggering immediate update check...");
      TotalUpdate.Daemon.Trigger_Check;
      Put_Line ("Check initiated. See daemon log for results.");
   end Run_Check;

   procedure Show_Status is
      Status : TotalUpdate.Daemon.Daemon_Status;
   begin
      Status := TotalUpdate.Daemon.Get_Status;

      Print_Banner;
      Put_Line ("Daemon Status:");
      Put_Line ("  Running:        " & Boolean'Image (Status.Is_Running));
      Put_Line ("  PID:            " & Natural'Image (Status.PID));
      Put_Line ("  Uptime:         " & Duration'Image (Status.Uptime) & "s");
      Put_Line ("  Last Check:     " & Status.Last_Check_Time);
      Put_Line ("  Next Check:     " & Status.Next_Check_Time);
      Put_Line ("  Updates Pending: " & Natural'Image (Status.Pending_Updates));
      New_Line;
      Put_Line ("Configuration:");
      Put_Line ("  Check Interval: " & Natural'Image (Status.Check_Interval_Secs) & "s");
      Put_Line ("  Auto Update:    " & Boolean'Image (Status.Auto_Update));
      Put_Line ("  Snapshot Method: " & Status.Snapshot_Method);
   end Show_Status;

begin
   Parse_Arguments;

   case Selected_Mode is
      when Mode_Help =>
         Print_Usage;

      when Mode_Version =>
         Put_Line ("TotalUpdate version " & Version);

      when Mode_Daemon =>
         Run_Daemon;

      when Mode_Check =>
         Run_Check;

      when Mode_Status =>
         Show_Status;
   end case;

exception
   when E : others =>
      Put_Line (Standard_Error, "Fatal error: " &
                Ada.Exceptions.Exception_Message (E));
      TotalUpdate.Logging.Error ("Fatal: " & Ada.Exceptions.Exception_Message (E));
      Set_Exit_Status (Failure);
end TotalUpdate_Main;
