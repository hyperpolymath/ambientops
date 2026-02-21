--  Terminal_ANSI - Lightweight ANSI terminal utilities for Ada
--
--  This library provides simple ANSI escape sequence handling for terminal
--  applications without requiring ncurses or other heavy dependencies.
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

package Terminal_ANSI is

   ---------------------------------------------------------------------------
   --  Terminal Dimensions
   ---------------------------------------------------------------------------

   --  Terminal size record
   type Terminal_Size is record
      Rows : Natural := 24;
      Cols : Natural := 80;
   end record;

   --  Detect terminal size from environment (LINES/COLUMNS)
   function Get_Terminal_Size return Terminal_Size;

   --  Get terminal rows
   function Get_Rows return Natural;

   --  Get terminal columns
   function Get_Cols return Natural;

   ---------------------------------------------------------------------------
   --  Screen Control
   ---------------------------------------------------------------------------

   --  Clear entire screen and move cursor to home
   procedure Clear_Screen;

   --  Clear from cursor to end of screen
   procedure Clear_To_End;

   --  Clear from cursor to beginning of screen
   procedure Clear_To_Beginning;

   --  Clear entire line
   procedure Clear_Line;

   --  Clear from cursor to end of line
   procedure Clear_Line_To_End;

   --  Clear from cursor to beginning of line
   procedure Clear_Line_To_Beginning;

   ---------------------------------------------------------------------------
   --  Cursor Control
   ---------------------------------------------------------------------------

   --  Move cursor to home position (1, 1)
   procedure Cursor_Home;

   --  Move cursor to specific position (1-indexed)
   procedure Move_Cursor (Row, Col : Positive);

   --  Move cursor up N lines
   procedure Cursor_Up (N : Positive := 1);

   --  Move cursor down N lines
   procedure Cursor_Down (N : Positive := 1);

   --  Move cursor right N columns
   procedure Cursor_Right (N : Positive := 1);

   --  Move cursor left N columns
   procedure Cursor_Left (N : Positive := 1);

   --  Save cursor position
   procedure Save_Cursor;

   --  Restore cursor position
   procedure Restore_Cursor;

   --  Show cursor
   procedure Show_Cursor;

   --  Hide cursor
   procedure Hide_Cursor;

   ---------------------------------------------------------------------------
   --  Alternate Screen Buffer
   ---------------------------------------------------------------------------

   --  Enter alternate screen buffer (for full-screen TUI apps)
   procedure Enter_Alternate_Screen;

   --  Exit alternate screen buffer (restore original content)
   procedure Exit_Alternate_Screen;

   ---------------------------------------------------------------------------
   --  Colors
   ---------------------------------------------------------------------------

   --  Standard foreground colors
   type Foreground_Color is
     (FG_Default,
      FG_Black, FG_Red, FG_Green, FG_Yellow,
      FG_Blue, FG_Magenta, FG_Cyan, FG_White,
      FG_Bright_Black, FG_Bright_Red, FG_Bright_Green, FG_Bright_Yellow,
      FG_Bright_Blue, FG_Bright_Magenta, FG_Bright_Cyan, FG_Bright_White);

   --  Standard background colors
   type Background_Color is
     (BG_Default,
      BG_Black, BG_Red, BG_Green, BG_Yellow,
      BG_Blue, BG_Magenta, BG_Cyan, BG_White,
      BG_Bright_Black, BG_Bright_Red, BG_Bright_Green, BG_Bright_Yellow,
      BG_Bright_Blue, BG_Bright_Magenta, BG_Bright_Cyan, BG_Bright_White);

   --  Text attributes
   type Text_Attribute is
     (Attr_Reset,
      Attr_Bold, Attr_Dim, Attr_Italic, Attr_Underline,
      Attr_Blink, Attr_Reverse, Attr_Hidden, Attr_Strikethrough);

   --  Set foreground color
   procedure Set_Foreground (Color : Foreground_Color);

   --  Set background color
   procedure Set_Background (Color : Background_Color);

   --  Set text attribute
   procedure Set_Attribute (Attr : Text_Attribute);

   --  Reset all attributes to default
   procedure Reset_Attributes;

   --  Set 256-color foreground (0-255)
   procedure Set_Foreground_256 (Color : Natural);

   --  Set 256-color background (0-255)
   procedure Set_Background_256 (Color : Natural);

   --  Set RGB foreground color (true color)
   procedure Set_Foreground_RGB (R, G, B : Natural);

   --  Set RGB background color (true color)
   procedure Set_Background_RGB (R, G, B : Natural);

   ---------------------------------------------------------------------------
   --  Raw Escape Sequences (for advanced use)
   ---------------------------------------------------------------------------

   --  CSI (Control Sequence Introducer) prefix
   CSI : constant String := ASCII.ESC & "[";

   --  Output raw escape sequence
   procedure Send_Escape (Sequence : String);

   --  Flush output
   procedure Flush_Output;

   ---------------------------------------------------------------------------
   --  Terminal State Management
   ---------------------------------------------------------------------------

   --  Initialize terminal for TUI use
   --  (enters alternate screen, hides cursor, detects size)
   procedure Initialize;

   --  Finalize terminal and restore state
   --  (exits alternate screen, shows cursor)
   procedure Finalize;

   --  Check if terminal has been initialized
   function Is_Initialized return Boolean;

end Terminal_ANSI;
