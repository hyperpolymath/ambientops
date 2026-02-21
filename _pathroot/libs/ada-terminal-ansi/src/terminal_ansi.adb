--  Terminal_ANSI - Lightweight ANSI terminal utilities for Ada
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Text_IO;
with Ada.Environment_Variables;

package body Terminal_ANSI is

   use Ada.Text_IO;

   --  State tracking
   Initialized : Boolean := False;
   Saved_Size  : Terminal_Size := (24, 80);

   ---------------------------------------------------------------------------
   --  Helper Functions
   ---------------------------------------------------------------------------

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   ---------------------------------------------------------------------------
   --  Terminal Dimensions
   ---------------------------------------------------------------------------

   function Get_Terminal_Size return Terminal_Size is
      Result : Terminal_Size := (24, 80);

      Lines_Str : constant String :=
        (if Ada.Environment_Variables.Exists ("LINES")
         then Ada.Environment_Variables.Value ("LINES")
         else "");

      Cols_Str : constant String :=
        (if Ada.Environment_Variables.Exists ("COLUMNS")
         then Ada.Environment_Variables.Value ("COLUMNS")
         else "");
   begin
      if Lines_Str'Length > 0 then
         begin
            Result.Rows := Natural'Value (Lines_Str);
         exception
            when others => Result.Rows := 24;
         end;
      end if;

      if Cols_Str'Length > 0 then
         begin
            Result.Cols := Natural'Value (Cols_Str);
         exception
            when others => Result.Cols := 80;
         end;
      end if;

      --  Enforce minimums
      if Result.Rows < 10 then Result.Rows := 24; end if;
      if Result.Cols < 40 then Result.Cols := 80; end if;

      return Result;
   end Get_Terminal_Size;

   function Get_Rows return Natural is
   begin
      return Get_Terminal_Size.Rows;
   end Get_Rows;

   function Get_Cols return Natural is
   begin
      return Get_Terminal_Size.Cols;
   end Get_Cols;

   ---------------------------------------------------------------------------
   --  Raw Output
   ---------------------------------------------------------------------------

   procedure Send_Escape (Sequence : String) is
   begin
      Put (Sequence);
   end Send_Escape;

   procedure Flush_Output is
   begin
      Flush;
   end Flush_Output;

   ---------------------------------------------------------------------------
   --  Screen Control
   ---------------------------------------------------------------------------

   procedure Clear_Screen is
   begin
      Send_Escape (CSI & "2J" & CSI & "H");
      Flush_Output;
   end Clear_Screen;

   procedure Clear_To_End is
   begin
      Send_Escape (CSI & "0J");
   end Clear_To_End;

   procedure Clear_To_Beginning is
   begin
      Send_Escape (CSI & "1J");
   end Clear_To_Beginning;

   procedure Clear_Line is
   begin
      Send_Escape (CSI & "2K");
   end Clear_Line;

   procedure Clear_Line_To_End is
   begin
      Send_Escape (CSI & "0K");
   end Clear_Line_To_End;

   procedure Clear_Line_To_Beginning is
   begin
      Send_Escape (CSI & "1K");
   end Clear_Line_To_Beginning;

   ---------------------------------------------------------------------------
   --  Cursor Control
   ---------------------------------------------------------------------------

   procedure Cursor_Home is
   begin
      Send_Escape (CSI & "H");
   end Cursor_Home;

   procedure Move_Cursor (Row, Col : Positive) is
   begin
      Send_Escape (CSI & Img (Row) & ";" & Img (Col) & "H");
   end Move_Cursor;

   procedure Cursor_Up (N : Positive := 1) is
   begin
      Send_Escape (CSI & Img (N) & "A");
   end Cursor_Up;

   procedure Cursor_Down (N : Positive := 1) is
   begin
      Send_Escape (CSI & Img (N) & "B");
   end Cursor_Down;

   procedure Cursor_Right (N : Positive := 1) is
   begin
      Send_Escape (CSI & Img (N) & "C");
   end Cursor_Right;

   procedure Cursor_Left (N : Positive := 1) is
   begin
      Send_Escape (CSI & Img (N) & "D");
   end Cursor_Left;

   procedure Save_Cursor is
   begin
      Send_Escape (CSI & "s");
   end Save_Cursor;

   procedure Restore_Cursor is
   begin
      Send_Escape (CSI & "u");
   end Restore_Cursor;

   procedure Show_Cursor is
   begin
      Send_Escape (CSI & "?25h");
   end Show_Cursor;

   procedure Hide_Cursor is
   begin
      Send_Escape (CSI & "?25l");
   end Hide_Cursor;

   ---------------------------------------------------------------------------
   --  Alternate Screen Buffer
   ---------------------------------------------------------------------------

   procedure Enter_Alternate_Screen is
   begin
      Send_Escape (CSI & "?1049h");
      Flush_Output;
   end Enter_Alternate_Screen;

   procedure Exit_Alternate_Screen is
   begin
      Send_Escape (CSI & "?1049l");
      Flush_Output;
   end Exit_Alternate_Screen;

   ---------------------------------------------------------------------------
   --  Colors
   ---------------------------------------------------------------------------

   procedure Set_Foreground (Color : Foreground_Color) is
      Code : constant array (Foreground_Color) of Natural :=
        (FG_Default        => 39,
         FG_Black          => 30, FG_Red     => 31, FG_Green   => 32, FG_Yellow => 33,
         FG_Blue           => 34, FG_Magenta => 35, FG_Cyan    => 36, FG_White  => 37,
         FG_Bright_Black   => 90, FG_Bright_Red => 91, FG_Bright_Green => 92,
         FG_Bright_Yellow  => 93, FG_Bright_Blue => 94, FG_Bright_Magenta => 95,
         FG_Bright_Cyan    => 96, FG_Bright_White => 97);
   begin
      Send_Escape (CSI & Img (Code (Color)) & "m");
   end Set_Foreground;

   procedure Set_Background (Color : Background_Color) is
      Code : constant array (Background_Color) of Natural :=
        (BG_Default        => 49,
         BG_Black          => 40, BG_Red     => 41, BG_Green   => 42, BG_Yellow => 43,
         BG_Blue           => 44, BG_Magenta => 45, BG_Cyan    => 46, BG_White  => 47,
         BG_Bright_Black   => 100, BG_Bright_Red => 101, BG_Bright_Green => 102,
         BG_Bright_Yellow  => 103, BG_Bright_Blue => 104, BG_Bright_Magenta => 105,
         BG_Bright_Cyan    => 106, BG_Bright_White => 107);
   begin
      Send_Escape (CSI & Img (Code (Color)) & "m");
   end Set_Background;

   procedure Set_Attribute (Attr : Text_Attribute) is
      Code : constant array (Text_Attribute) of Natural :=
        (Attr_Reset         => 0,
         Attr_Bold          => 1,
         Attr_Dim           => 2,
         Attr_Italic        => 3,
         Attr_Underline     => 4,
         Attr_Blink         => 5,
         Attr_Reverse       => 7,
         Attr_Hidden        => 8,
         Attr_Strikethrough => 9);
   begin
      Send_Escape (CSI & Img (Code (Attr)) & "m");
   end Set_Attribute;

   procedure Reset_Attributes is
   begin
      Send_Escape (CSI & "0m");
   end Reset_Attributes;

   procedure Set_Foreground_256 (Color : Natural) is
   begin
      Send_Escape (CSI & "38;5;" & Img (Color mod 256) & "m");
   end Set_Foreground_256;

   procedure Set_Background_256 (Color : Natural) is
   begin
      Send_Escape (CSI & "48;5;" & Img (Color mod 256) & "m");
   end Set_Background_256;

   procedure Set_Foreground_RGB (R, G, B : Natural) is
   begin
      Send_Escape (CSI & "38;2;" &
        Img (R mod 256) & ";" &
        Img (G mod 256) & ";" &
        Img (B mod 256) & "m");
   end Set_Foreground_RGB;

   procedure Set_Background_RGB (R, G, B : Natural) is
   begin
      Send_Escape (CSI & "48;2;" &
        Img (R mod 256) & ";" &
        Img (G mod 256) & ";" &
        Img (B mod 256) & "m");
   end Set_Background_RGB;

   ---------------------------------------------------------------------------
   --  Terminal State Management
   ---------------------------------------------------------------------------

   procedure Initialize is
   begin
      if Initialized then
         return;
      end if;

      Saved_Size := Get_Terminal_Size;
      Enter_Alternate_Screen;
      Hide_Cursor;
      Clear_Screen;
      Initialized := True;
   end Initialize;

   procedure Finalize is
   begin
      if not Initialized then
         return;
      end if;

      Reset_Attributes;
      Clear_Screen;
      Show_Cursor;
      Exit_Alternate_Screen;
      Initialized := False;
   end Finalize;

   function Is_Initialized return Boolean is
   begin
      return Initialized;
   end Is_Initialized;

end Terminal_ANSI;
