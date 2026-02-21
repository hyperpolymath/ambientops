-------------------------------------------------------------------------------
--  nano-aider - TUI Components (Body)
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

with Ada.Strings.Fixed;
with Nano_Aider.Options;
with Nano_Aider.Config;

package body Nano_Aider.TUI is

   use type Curses.Real_Key_Code;
   use type Curses.Color_Pair;

   Screen_Height : Curses.Line_Position;
   Screen_Width  : Curses.Column_Position;
   Running       : Boolean := True;

   --  Key codes
   Key_Q     : constant Curses.Real_Key_Code := Character'Pos ('q');
   Key_H     : constant Curses.Real_Key_Code := Character'Pos ('h');
   Key_J     : constant Curses.Real_Key_Code := Character'Pos ('j');
   Key_K     : constant Curses.Real_Key_Code := Character'Pos ('k');
   Key_Enter : constant Curses.Real_Key_Code := 10;
   Key_Slash : constant Curses.Real_Key_Code := Character'Pos ('/');
   Key_Esc   : constant Curses.Real_Key_Code := 27;

   ---------------------------------------------------------------------------
   procedure Initialize_Colors is
   begin
      Curses.Init_Pair (CP_Normal,    Curses.White,   Curses.Black);
      Curses.Init_Pair (CP_Highlight, Curses.Black,   Curses.Cyan);
      Curses.Init_Pair (CP_Header,    Curses.White,   Curses.Blue);
      Curses.Init_Pair (CP_Status,    Curses.Black,   Curses.White);
      Curses.Init_Pair (CP_Warning,   Curses.Yellow,  Curses.Black);
      Curses.Init_Pair (CP_Success,   Curses.Green,   Curses.Black);
      Curses.Init_Pair (CP_Hidden,    Curses.Magenta, Curses.Black);
   end Initialize_Colors;

   ---------------------------------------------------------------------------
   procedure Draw_Header is
      Title : constant String := " nano-aider - Editor Configuration TUI ";
   begin
      Curses.Set_Color (Curses.Standard_Window, CP_Header);
      Curses.Move_Cursor (Curses.Standard_Window, 0, 0);
      Curses.Add (Curses.Standard_Window, String'(1 .. Integer (Screen_Width) => ' '));
      Curses.Move_Cursor (Curses.Standard_Window, 0,
                          Curses.Column_Position ((Integer (Screen_Width) - Title'Length) / 2));
      Curses.Add (Curses.Standard_Window, Title);
      Curses.Set_Color (Curses.Standard_Window, CP_Normal);
   end Draw_Header;

   ---------------------------------------------------------------------------
   procedure Draw_Status_Bar (Message : String := "") is
      Status  : constant String := " [h]elp | [/]search | [q]uit | [Enter]select | [Esc]back ";
      Display : constant String := (if Message'Length > 0 then Message else Status);
   begin
      Curses.Set_Color (Curses.Standard_Window, CP_Status);
      Curses.Move_Cursor (Curses.Standard_Window, Screen_Height - 1, 0);
      Curses.Add (Curses.Standard_Window, String'(1 .. Integer (Screen_Width) => ' '));
      Curses.Move_Cursor (Curses.Standard_Window, Screen_Height - 1, 1);
      Curses.Add (Curses.Standard_Window, Display);
      Curses.Set_Color (Curses.Standard_Window, CP_Normal);
   end Draw_Status_Bar;

   ---------------------------------------------------------------------------
   procedure Draw_Categories is
      Categories : constant Nano_Aider.Options.Category_Array :=
        Nano_Aider.Options.Get_Categories;
      Y : Curses.Line_Position := 2;
   begin
      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Add (Curses.Standard_Window, "Configuration Categories:");
      Y := Y + 2;

      for I in Categories'Range loop
         if I = Current_Category then
            Curses.Set_Color (Curses.Standard_Window, CP_Highlight);
         else
            Curses.Set_Color (Curses.Standard_Window, CP_Normal);
         end if;

         Curses.Move_Cursor (Curses.Standard_Window, Y, 4);
         Curses.Add (Curses.Standard_Window,
                     (if I = Current_Category then "> " else "  ") &
                     Categories (I).Name.all & " (" &
                     Natural'Image (Categories (I).Option_Count) & " options)");
         Y := Y + 1;
      end loop;

      Curses.Set_Color (Curses.Standard_Window, CP_Normal);
   end Draw_Categories;

   ---------------------------------------------------------------------------
   procedure Draw_Options is
      Opts : constant Nano_Aider.Options.Option_Array :=
        Nano_Aider.Options.Get_Options_For_Category (Current_Category);
      Y : Curses.Line_Position := 2;
   begin
      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Add (Curses.Standard_Window, "Options (showing " &
                  (if Show_Hidden then "all" else "visible only") & "):");
      Y := Y + 2;

      for I in Opts'Range loop
         declare
            Opt : constant Nano_Aider.Options.Option_Record := Opts (I);
         begin
            if Show_Hidden or not Opt.Is_Hidden then
               if I = Current_Option then
                  Curses.Set_Color (Curses.Standard_Window, CP_Highlight);
               elsif Opt.Is_Hidden then
                  Curses.Set_Color (Curses.Standard_Window, CP_Hidden);
               else
                  Curses.Set_Color (Curses.Standard_Window, CP_Normal);
               end if;

               Curses.Move_Cursor (Curses.Standard_Window, Y, 4);
               Curses.Add (Curses.Standard_Window,
                           (if I = Current_Option then "> " else "  ") &
                           Opt.Name.all &
                           (if Opt.Is_Hidden then " [hidden]" else ""));
               Y := Y + 1;
            end if;
         end;
      end loop;

      Curses.Set_Color (Curses.Standard_Window, CP_Normal);
   end Draw_Options;

   ---------------------------------------------------------------------------
   procedure Draw_Option_Detail is
      Opt : constant Nano_Aider.Options.Option_Record :=
        Nano_Aider.Options.Get_Option (Current_Category, Current_Option);
      Y : Curses.Line_Position := 2;
   begin
      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Set_Color (Curses.Standard_Window, CP_Header);
      Curses.Add (Curses.Standard_Window, Opt.Name.all);
      Y := Y + 2;

      Curses.Set_Color (Curses.Standard_Window, CP_Normal);
      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Add (Curses.Standard_Window, "Description:");
      Y := Y + 1;
      Curses.Move_Cursor (Curses.Standard_Window, Y, 4);
      Curses.Add (Curses.Standard_Window, Opt.Description.all);
      Y := Y + 2;

      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Add (Curses.Standard_Window, "Type: " & Opt.Value_Type.all);
      Y := Y + 1;

      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Add (Curses.Standard_Window, "Default: " & Opt.Default_Value.all);
      Y := Y + 1;

      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Add (Curses.Standard_Window, "Current: " & Opt.Current_Value.all);
      Y := Y + 2;

      if Opt.Is_Hidden then
         Curses.Set_Color (Curses.Standard_Window, CP_Warning);
         Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
         Curses.Add (Curses.Standard_Window,
                     "** This is a hidden/undocumented option **");
         Y := Y + 1;
      end if;

      if Opt.Nano_Version.all /= "" then
         Curses.Set_Color (Curses.Standard_Window, CP_Normal);
         Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
         Curses.Add (Curses.Standard_Window,
                     "Available since: nano " & Opt.Nano_Version.all);
      end if;
   end Draw_Option_Detail;

   ---------------------------------------------------------------------------
   procedure Draw_Help is
      Y : Curses.Line_Position := 2;
   begin
      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Set_Color (Curses.Standard_Window, CP_Header);
      Curses.Add (Curses.Standard_Window, "nano-aider Help");
      Y := Y + 2;

      Curses.Set_Color (Curses.Standard_Window, CP_Normal);
      declare
         type Help_Entry is record
            Key  : access constant String;
            Desc : access constant String;
         end record;

         K1 : aliased constant String := "j/Down";
         D1 : aliased constant String := "Move cursor down";
         K2 : aliased constant String := "k/Up";
         D2 : aliased constant String := "Move cursor up";
         K3 : aliased constant String := "Enter";
         D3 : aliased constant String := "Select item / Enter submenu";
         K4 : aliased constant String := "Esc/Backspace";
         D4 : aliased constant String := "Go back / Exit submenu";
         K5 : aliased constant String := "/";
         D5 : aliased constant String := "Start search";
         K6 : aliased constant String := "h";
         D6 : aliased constant String := "Toggle hidden options";
         K7 : aliased constant String := "e";
         D7 : aliased constant String := "Export configuration";
         K8 : aliased constant String := "r";
         D8 : aliased constant String := "Reload configuration";
         K9 : aliased constant String := "q";
         D9 : aliased constant String := "Quit nano-aider";

         Help_Items : constant array (1 .. 9) of Help_Entry :=
           ((K1'Access, D1'Access), (K2'Access, D2'Access),
            (K3'Access, D3'Access), (K4'Access, D4'Access),
            (K5'Access, D5'Access), (K6'Access, D6'Access),
            (K7'Access, D7'Access), (K8'Access, D8'Access),
            (K9'Access, D9'Access));
      begin
         for Item of Help_Items loop
            Curses.Move_Cursor (Curses.Standard_Window, Y, 4);
            Curses.Set_Color (Curses.Standard_Window, CP_Highlight);
            Curses.Add (Curses.Standard_Window, Item.Key.all);
            Curses.Set_Color (Curses.Standard_Window, CP_Normal);
            Curses.Move_Cursor (Curses.Standard_Window, Y, 20);
            Curses.Add (Curses.Standard_Window, Item.Desc.all);
            Y := Y + 1;
         end loop;
      end;
   end Draw_Help;

   ---------------------------------------------------------------------------
   procedure Draw_Search is
      Y : Curses.Line_Position := 2;
   begin
      Curses.Move_Cursor (Curses.Standard_Window, Y, 2);
      Curses.Add (Curses.Standard_Window, "Search: " &
                  Search_Query (1 .. Search_Length) & "_");
   end Draw_Search;

   ---------------------------------------------------------------------------
   procedure Handle_Key (Key : Curses.Real_Key_Code) is
   begin
      if Search_Active then
         if Key = Key_Esc then
            Search_Active := False;
            Search_Length := 0;
         elsif Key = Key_Enter then
            Execute_Search;
            Search_Active := False;
         elsif Key >= 32 and Key < 127 then
            if Search_Length < Search_Query'Last then
               Search_Length := Search_Length + 1;
               Search_Query (Search_Length) := Character'Val (Key);
            end if;
         end if;
         return;
      end if;

      case Key is
         when Key_Q =>
            Running := False;

         when Key_H =>
            if Current_View = View_Help then
               Current_View := View_Categories;
            else
               Current_View := View_Help;
            end if;

         when Key_J | Curses.Key_Cursor_Down =>
            Navigate_Down;

         when Key_K | Curses.Key_Cursor_Up =>
            Navigate_Up;

         when Key_Enter =>
            Navigate_Select;

         when Key_Esc | Curses.Key_Backspace =>
            Navigate_Back;

         when Key_Slash =>
            Start_Search;

         when others =>
            null;
      end case;
   end Handle_Key;

   ---------------------------------------------------------------------------
   procedure Navigate_Up is
   begin
      case Current_View is
         when View_Categories =>
            if Current_Category > 0 then
               Current_Category := Current_Category - 1;
            end if;
         when View_Options =>
            if Current_Option > 0 then
               Current_Option := Current_Option - 1;
            end if;
         when others =>
            null;
      end case;
   end Navigate_Up;

   ---------------------------------------------------------------------------
   procedure Navigate_Down is
      Max_Cat : constant Natural := Nano_Aider.Options.Category_Count - 1;
      Max_Opt : constant Natural :=
        Nano_Aider.Options.Option_Count (Current_Category) - 1;
   begin
      case Current_View is
         when View_Categories =>
            if Current_Category < Max_Cat then
               Current_Category := Current_Category + 1;
            end if;
         when View_Options =>
            if Current_Option < Max_Opt then
               Current_Option := Current_Option + 1;
            end if;
         when others =>
            null;
      end case;
   end Navigate_Down;

   ---------------------------------------------------------------------------
   procedure Navigate_Select is
   begin
      case Current_View is
         when View_Categories =>
            Current_View := View_Options;
            Current_Option := 0;
         when View_Options =>
            Current_View := View_Option_Detail;
         when others =>
            null;
      end case;
   end Navigate_Select;

   ---------------------------------------------------------------------------
   procedure Navigate_Back is
   begin
      case Current_View is
         when View_Option_Detail =>
            Current_View := View_Options;
         when View_Options =>
            Current_View := View_Categories;
         when View_Help | View_Search =>
            Current_View := View_Categories;
         when others =>
            null;
      end case;
   end Navigate_Back;

   ---------------------------------------------------------------------------
   procedure Toggle_Hidden_Options is
   begin
      Show_Hidden := not Show_Hidden;
   end Toggle_Hidden_Options;

   ---------------------------------------------------------------------------
   procedure Start_Search is
   begin
      Search_Active := True;
      Search_Length := 0;
      Current_View := View_Search;
   end Start_Search;

   ---------------------------------------------------------------------------
   procedure Update_Search (Char : Character) is
   begin
      if Search_Length < Search_Query'Last then
         Search_Length := Search_Length + 1;
         Search_Query (Search_Length) := Char;
      end if;
   end Update_Search;

   ---------------------------------------------------------------------------
   procedure Execute_Search is
   begin
      --  Search through options and navigate to first match
      Nano_Aider.Options.Search (Search_Query (1 .. Search_Length));
      Current_View := View_Options;
   end Execute_Search;

   ---------------------------------------------------------------------------
   procedure Main_Loop is
      Key : Curses.Real_Key_Code;
   begin
      Curses.Get_Size (Curses.Standard_Window, Screen_Height, Screen_Width);

      while Running loop
         Curses.Erase;
         Draw_Header;

         case Current_View is
            when View_Categories =>
               Draw_Categories;
            when View_Options =>
               Draw_Options;
            when View_Option_Detail =>
               Draw_Option_Detail;
            when View_Help =>
               Draw_Help;
            when View_Search =>
               Draw_Search;
            when View_Profiles =>
               Draw_Categories; -- placeholder
         end case;

         Draw_Status_Bar;
         Curses.Refresh;

         Key := Curses.Get_Keystroke;
         Handle_Key (Key);
      end loop;

      Curses.End_Windows;
   end Main_Loop;

end Nano_Aider.TUI;
