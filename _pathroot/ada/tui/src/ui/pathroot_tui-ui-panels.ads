--  _pathroot TUI - UI Panels Specification
--  Terminal UI panel management
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Pathroot_TUI.Core.Envbase; use Pathroot_TUI.Core.Envbase;

package Pathroot_TUI.UI.Panels is

   --  Initialize the terminal UI
   procedure Initialize_UI;

   --  Finalize and cleanup the terminal UI
   procedure Finalize_UI;

   --  Draw a specific panel
   procedure Draw_Panel (Panel : Panel_ID; Env_Info : Environment_Info);

   --  Handle user input
   procedure Handle_Input (Panel : in out Panel_ID; Running : in out Boolean);

   --  Draw the header bar
   procedure Draw_Header (Env_Info : Environment_Info);

   --  Draw the footer with key hints
   procedure Draw_Footer;

   --  Clear the screen
   procedure Clear_Screen;

   --  Get terminal dimensions
   procedure Get_Terminal_Size (Rows : out Natural; Cols : out Natural);

end Pathroot_TUI.UI.Panels;
