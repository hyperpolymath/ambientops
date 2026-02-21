--  _pathroot TUI - Main Package Specification
--  Ada-based Terminal User Interface for devtools environment management
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

package Pathroot_TUI is

   --  Application version
   Version : constant String := "0.1.0";

   --  Exit codes
   Exit_Success : constant := 0;
   Exit_Failure : constant := 1;
   Exit_No_Pathroot : constant := 2;

   --  Maximum path length
   Max_Path_Length : constant := 4096;

   --  Panel identifiers
   type Panel_ID is
     (Panel_Environment,
      Panel_PATH,
      Panel_Links,
      Panel_Logs,
      Panel_Help);

   --  Application modes
   type App_Mode is
     (Mode_Interactive,
      Mode_Transaction);

   --  Run the TUI application
   procedure Run;

   --  Run in transaction mode (for scripting)
   procedure Run_Transaction;

   --  Print help message
   procedure Print_Help;

end Pathroot_TUI;
