--  _pathroot TUI - Main Package Body
--  Ada-based Terminal User Interface for devtools environment management
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;      use Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Pathroot_TUI.Core.Discovery;
with Pathroot_TUI.Core.Envbase;
with Pathroot_TUI.UI.Panels;
with Pathroot_TUI.Core.Transactions;

package body Pathroot_TUI is

   --  Current application state
   Current_Panel : Panel_ID := Panel_Environment;
   Current_Mode  : App_Mode := Mode_Interactive;
   Running       : Boolean := True;

   --  Environment state
   Devtools_Root : Unbounded_String := Null_Unbounded_String;
   Pathroot_File : Unbounded_String := Null_Unbounded_String;

   ---------
   -- Run --
   ---------

   procedure Run is
      use Pathroot_TUI.Core.Discovery;
      use Pathroot_TUI.Core.Envbase;
      use Pathroot_TUI.UI.Panels;

      Env_Info : Environment_Info;
   begin
      --  Parse command line arguments
      for I in 1 .. Argument_Count loop
         if Argument (I) = "--transaction" or Argument (I) = "-t" then
            Current_Mode := Mode_Transaction;
         elsif Argument (I) = "--help" or Argument (I) = "-h" then
            Print_Help;
            return;
         elsif Argument (I) = "--version" or Argument (I) = "-v" then
            Put_Line ("pathroot-tui v" & Version);
            return;
         end if;
      end loop;

      --  Discover _pathroot
      if not Discover_Pathroot (Pathroot_File, Devtools_Root) then
         Put_Line (Standard_Error, "ERROR: _pathroot not found");
         Put_Line (Standard_Error,
           "Run 'automkdir.bat' (Windows) or 'pathroot.sh init' (POSIX) first.");
         Set_Exit_Status (Exit_No_Pathroot);
         return;
      end if;

      --  Load environment info
      Env_Info := Load_Environment (To_String (Devtools_Root));

      --  Branch based on mode
      case Current_Mode is
         when Mode_Transaction =>
            Run_Transaction;

         when Mode_Interactive =>
            --  Initialize UI
            Initialize_UI;

            --  Main loop
            while Running loop
               Draw_Panel (Current_Panel, Env_Info);
               Handle_Input (Current_Panel, Running);
            end loop;

            --  Cleanup
            Finalize_UI;
      end case;

      Set_Exit_Status (Exit_Success);
   end Run;

   ---------------------
   -- Run_Transaction --
   ---------------------

   procedure Run_Transaction is
      use Pathroot_TUI.Core.Transactions;
      Line : String (1 .. 1024);
      Last : Natural;
   begin
      --  Read commands from stdin
      while not End_Of_File loop
         Get_Line (Line, Last);
         if Last > 0 then
            Process_Command (Line (1 .. Last), To_String (Devtools_Root));
         end if;
      end loop;
   end Run_Transaction;

   ----------------
   -- Print_Help --
   ----------------

   procedure Print_Help is
   begin
      Put_Line ("_pathroot TUI v" & Version);
      Put_Line ("");
      Put_Line ("Usage: pathroot-tui [options]");
      Put_Line ("");
      Put_Line ("Options:");
      Put_Line ("  -t, --transaction    Run in transaction mode (for scripting)");
      Put_Line ("  -h, --help           Show this help message");
      Put_Line ("  -v, --version        Show version");
      Put_Line ("");
      Put_Line ("Interactive Controls:");
      Put_Line ("  E    Environment browser");
      Put_Line ("  P    PATH editor");
      Put_Line ("  L    Link manager");
      Put_Line ("  G    Log viewer");
      Put_Line ("  Q    Quit");
      Put_Line ("  ?    Help");
      Put_Line ("");
      Put_Line ("Transaction Commands:");
      Put_Line ("  PATHROOT:QUERY:ENV           Get environment info");
      Put_Line ("  PATHROOT:SET:PROFILE:<name>  Switch profile");
      Put_Line ("  PATHROOT:LINK:<src>:<dst>    Create symbolic link");
      Put_Line ("  PATHROOT:AUDIT:links         Audit all links");
   end Print_Help;

end Pathroot_TUI;
