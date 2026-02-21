-------------------------------------------------------------------------------
--  nano-aider - Ada TUI for nano/micro Editor Configuration
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Directories;
with Terminal_Interface.Curses;
with Terminal_Interface.Curses.Panels;

with Nano_Aider.TUI;
with Nano_Aider.Config;
with Nano_Aider.Options;
with Nano_Aider.Profiles;

procedure Nano_Aider is
   package TIO renames Ada.Text_IO;
   package CLI renames Ada.Command_Line;
   package Curses renames Terminal_Interface.Curses;

   Version : constant String := "0.1.0";

   procedure Show_Version is
   begin
      TIO.Put_Line ("nano-aider v" & Version);
      TIO.Put_Line ("Ada TUI for nano/micro Editor Configuration");
      TIO.Put_Line ("Copyright (C) 2024-2025 Jonathan D.A. Jewell");
   end Show_Version;

   procedure Show_Help is
   begin
      TIO.Put_Line ("Usage: nano-aider [OPTIONS]");
      TIO.New_Line;
      TIO.Put_Line ("Options:");
      TIO.Put_Line ("  -h, --help      Show this help message");
      TIO.Put_Line ("  -v, --version   Show version information");
      TIO.Put_Line ("  -c, --config    Specify config file path");
      TIO.Put_Line ("  -p, --profile   Load a configuration profile");
      TIO.Put_Line ("  -l, --list      List all nano options (hidden included)");
      TIO.Put_Line ("  -e, --export    Export current config to file");
      TIO.Put_Line ("  --micro         Configure micro editor instead of nano");
      TIO.New_Line;
      TIO.Put_Line ("Interactive Mode:");
      TIO.Put_Line ("  Run without arguments to launch the TUI");
   end Show_Help;

   procedure Run_TUI is
      Main_Window : Curses.Window;
   begin
      --  Initialize curses
      Curses.Init_Screen;
      Curses.Set_Cbreak_Mode (True);
      Curses.Set_Echo_Mode (False);
      Curses.Set_KeyPad_Mode (Curses.Standard_Window, True);

      --  Check for color support
      if Curses.Has_Colors then
         Curses.Start_Color;
         Nano_Aider.TUI.Initialize_Colors;
      end if;

      --  Load configuration
      Nano_Aider.Config.Load_Default;
      Nano_Aider.Options.Discover_All;

      --  Run main TUI loop
      Nano_Aider.TUI.Main_Loop;

   exception
      when others =>
         Curses.End_Windows;
         raise;
   end Run_TUI;

begin
   --  Parse command line arguments
   if CLI.Argument_Count > 0 then
      declare
         Arg : constant String := CLI.Argument (1);
      begin
         if Arg = "-h" or Arg = "--help" then
            Show_Help;
            return;
         elsif Arg = "-v" or Arg = "--version" then
            Show_Version;
            return;
         elsif Arg = "-l" or Arg = "--list" then
            Nano_Aider.Options.List_All_Options;
            return;
         end if;
      end;
   end if;

   --  Launch TUI
   Run_TUI;
end Nano_Aider;
