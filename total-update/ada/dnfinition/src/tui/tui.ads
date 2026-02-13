--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TUI - Terminal User Interface root package for DNFinition
--  Provides ncurses-based interface similar to aptitude/nala

package TUI is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Color Schemes (inspired by nala)
   --  ═══════════════════════════════════════════════════════════════════════

   type Color_Pair is
     (Default,
      Header,           --  Blue background
      Selected,         --  Highlighted item
      Installed,        --  Green
      Upgradable,       --  Yellow
      To_Install,       --  Light green
      To_Remove,        --  Red
      To_Upgrade,       --  Light blue
      Pinned,           --  Cyan
      Broken,           --  Bright red
      Status_Bar,       --  Bottom status
      Status_Error,     --  Red status
      Status_Success,   --  Green status
      Search_Match);    --  Search highlight

   --  ═══════════════════════════════════════════════════════════════════════
   --  Layout Constants
   --  ═══════════════════════════════════════════════════════════════════════

   Header_Height   : constant := 3;
   Footer_Height   : constant := 2;
   Sidebar_Width   : constant := 30;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Unicode Box Drawing (for pretty borders)
   --  ═══════════════════════════════════════════════════════════════════════

   Box_Horizontal  : constant String := "─";
   Box_Vertical    : constant String := "│";
   Box_Top_Left    : constant String := "┌";
   Box_Top_Right   : constant String := "┐";
   Box_Bottom_Left : constant String := "└";
   Box_Bottom_Right: constant String := "┘";
   Box_T_Down      : constant String := "┬";
   Box_T_Up        : constant String := "┴";
   Box_T_Right     : constant String := "├";
   Box_T_Left      : constant String := "┤";
   Box_Cross       : constant String := "┼";

   --  Double-line variants for headers
   DBox_Horizontal  : constant String := "═";
   DBox_Vertical    : constant String := "║";
   DBox_Top_Left    : constant String := "╔";
   DBox_Top_Right   : constant String := "╗";
   DBox_Bottom_Left : constant String := "╚";
   DBox_Bottom_Right: constant String := "╝";

   --  ═══════════════════════════════════════════════════════════════════════
   --  Status Indicators
   --  ═══════════════════════════════════════════════════════════════════════

   Icon_Installed  : constant String := "✓";
   Icon_Upgradable : constant String := "↑";
   Icon_To_Install : constant String := "+";
   Icon_To_Remove  : constant String := "-";
   Icon_Pinned     : constant String := "⚑";
   Icon_Broken     : constant String := "✗";
   Icon_Automatic  : constant String := "A";
   Icon_Manual     : constant String := "M";

end TUI;
