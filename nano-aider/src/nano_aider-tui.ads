-------------------------------------------------------------------------------
--  nano-aider - TUI Components
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

with Terminal_Interface.Curses;

package Nano_Aider.TUI is

   package Curses renames Terminal_Interface.Curses;

   --  Color pair definitions
   CP_Normal      : constant Curses.Color_Pair := 1;
   CP_Highlight   : constant Curses.Color_Pair := 2;
   CP_Header      : constant Curses.Color_Pair := 3;
   CP_Status      : constant Curses.Color_Pair := 4;
   CP_Warning     : constant Curses.Color_Pair := 5;
   CP_Success     : constant Curses.Color_Pair := 6;
   CP_Hidden      : constant Curses.Color_Pair := 7;

   --  View modes
   type View_Mode is
     (View_Categories,
      View_Options,
      View_Option_Detail,
      View_Profiles,
      View_Search,
      View_Help);

   --  Initialize color pairs
   procedure Initialize_Colors;

   --  Main TUI loop
   procedure Main_Loop;

   --  Draw routines
   procedure Draw_Header;
   procedure Draw_Status_Bar (Message : String := "");
   procedure Draw_Categories;
   procedure Draw_Options;
   procedure Draw_Option_Detail;
   procedure Draw_Help;
   procedure Draw_Search;

   --  Navigation
   procedure Handle_Key (Key : Curses.Real_Key_Code);
   procedure Navigate_Up;
   procedure Navigate_Down;
   procedure Navigate_Select;
   procedure Navigate_Back;
   procedure Toggle_Hidden_Options;

   --  Search
   procedure Start_Search;
   procedure Update_Search (Char : Character);
   procedure Execute_Search;

private

   Current_View     : View_Mode := View_Categories;
   Current_Category : Natural := 0;
   Current_Option   : Natural := 0;
   Show_Hidden      : Boolean := True;
   Search_Active    : Boolean := False;
   Search_Query     : String (1 .. 256);
   Search_Length    : Natural := 0;

end Nano_Aider.TUI;
