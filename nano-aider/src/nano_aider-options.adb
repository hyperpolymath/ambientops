-------------------------------------------------------------------------------
--  nano-aider - Options Discovery and Management (Body)
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Characters.Handling;

package body Nano_Aider.Options is

   package TIO renames Ada.Text_IO;

   --  Static category names
   Cat_Display     : aliased constant String := "Display";
   Cat_Editing     : aliased constant String := "Editing";
   Cat_Interface   : aliased constant String := "Interface";
   Cat_Search      : aliased constant String := "Search & Replace";
   Cat_Files       : aliased constant String := "Files";
   Cat_Backup      : aliased constant String := "Backup";
   Cat_Syntax      : aliased constant String := "Syntax Highlighting";
   Cat_Keybindings : aliased constant String := "Key Bindings";
   Cat_Hidden      : aliased constant String := "Hidden/Undocumented";
   Cat_Micro       : aliased constant String := "Micro-Specific";

   Desc_Display     : aliased constant String := "Visual display options";
   Desc_Editing     : aliased constant String := "Text editing behavior";
   Desc_Interface   : aliased constant String := "User interface elements";
   Desc_Search      : aliased constant String := "Search and replace settings";
   Desc_Files       : aliased constant String := "File handling options";
   Desc_Backup      : aliased constant String := "Backup and recovery";
   Desc_Syntax      : aliased constant String := "Syntax highlighting rules";
   Desc_Keybindings : aliased constant String := "Custom key bindings";
   Desc_Hidden      : aliased constant String := "Undocumented advanced options";
   Desc_Micro       : aliased constant String := "Options specific to micro editor";

   --  Sample option names for the hidden category
   Opt_Stateflags      : aliased constant String := "stateflags";
   Opt_Minibar         : aliased constant String := "minibar";
   Opt_Zero            : aliased constant String := "zero";
   Opt_Indicator       : aliased constant String := "indicator";
   Opt_Jumpyscrolling  : aliased constant String := "jumpyscrolling";
   Opt_Emptyline       : aliased constant String := "emptyline";
   Opt_Guidestripe     : aliased constant String := "guidestripe";
   Opt_Bookstyle       : aliased constant String := "bookstyle";
   Opt_Locking         : aliased constant String := "locking";
   Opt_Zap             : aliased constant String := "zap";

   --  Sample descriptions
   Desc_Stateflags     : aliased constant String := "Display editing state flags in title bar";
   Desc_Minibar        : aliased constant String := "Show compact status bar instead of full one";
   Desc_Zero           : aliased constant String := "Hide all interface elements except text";
   Desc_Indicator      : aliased constant String := "Show scroll position indicator";
   Desc_Jumpyscrolling : aliased constant String := "Scroll by half-screen instead of line by line";
   Desc_Emptyline      : aliased constant String := "Keep an empty line below title bar";
   Desc_Guidestripe    : aliased constant String := "Draw vertical stripe at specified column";
   Desc_Bookstyle      : aliased constant String := "Use book-style justification";
   Desc_Locking        : aliased constant String := "Use lock files to prevent concurrent edits";
   Desc_Zap            : aliased constant String := "Delete selected region without copying";

   --  Type strings
   Type_Boolean : aliased constant String := "boolean";
   Type_Integer : aliased constant String := "integer";
   Type_String  : aliased constant String := "string";

   Val_False : aliased constant String := "false";
   Val_True  : aliased constant String := "true";
   Val_Empty : aliased constant String := "";

   Ver_2_0  : aliased constant String := "2.0";
   Ver_4_0  : aliased constant String := "4.0";
   Ver_5_0  : aliased constant String := "5.0";
   Ver_6_0  : aliased constant String := "6.0";
   Ver_7_0  : aliased constant String := "7.0";

   --  Static categories
   Categories : constant Category_Array (0 .. 9) :=
     ((Cat_Display'Access,     Desc_Display'Access,     15),
      (Cat_Editing'Access,     Desc_Editing'Access,     12),
      (Cat_Interface'Access,   Desc_Interface'Access,   8),
      (Cat_Search'Access,      Desc_Search'Access,      6),
      (Cat_Files'Access,       Desc_Files'Access,       10),
      (Cat_Backup'Access,      Desc_Backup'Access,      5),
      (Cat_Syntax'Access,      Desc_Syntax'Access,      20),
      (Cat_Keybindings'Access, Desc_Keybindings'Access, 50),
      (Cat_Hidden'Access,      Desc_Hidden'Access,      25),
      (Cat_Micro'Access,       Desc_Micro'Access,       30));

   --  Hidden options sample
   Hidden_Options : constant Option_Array (0 .. 9) :=
     ((Opt_Stateflags'Access, Desc_Stateflags'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_6_0'Access, False),
      (Opt_Minibar'Access, Desc_Minibar'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_6_0'Access, False),
      (Opt_Zero'Access, Desc_Zero'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_7_0'Access, False),
      (Opt_Indicator'Access, Desc_Indicator'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_5_0'Access, False),
      (Opt_Jumpyscrolling'Access, Desc_Jumpyscrolling'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_4_0'Access, False),
      (Opt_Emptyline'Access, Desc_Emptyline'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_5_0'Access, False),
      (Opt_Guidestripe'Access, Desc_Guidestripe'Access, Type_Integer'Access,
       Val_Empty'Access, Val_Empty'Access, True, False, Ver_5_0'Access, True),
      (Opt_Bookstyle'Access, Desc_Bookstyle'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_6_0'Access, False),
      (Opt_Locking'Access, Desc_Locking'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_4_0'Access, False),
      (Opt_Zap'Access, Desc_Zap'Access, Type_Boolean'Access,
       Val_False'Access, Val_False'Access, True, False, Ver_5_0'Access, False));

   Search_Result_Count : Natural := 0;

   ---------------------------------------------------------------------------
   procedure Discover_All is
   begin
      --  In a full implementation, this would:
      --  1. Parse nano --help output
      --  2. Read /usr/share/nano/*.nanorc files
      --  3. Check nano version for available options
      --  4. Detect undocumented options from source code analysis
      null;
   end Discover_All;

   ---------------------------------------------------------------------------
   procedure List_All_Options is
   begin
      TIO.Put_Line ("nano-aider: All Configuration Options");
      TIO.Put_Line ("=====================================");
      TIO.New_Line;

      for Cat of Categories loop
         TIO.Put_Line ("[" & Cat.Name.all & "]");
         TIO.Put_Line ("  " & Cat.Description.all);
         TIO.Put_Line ("  Options:" & Natural'Image (Cat.Option_Count));
         TIO.New_Line;
      end loop;

      TIO.Put_Line ("Hidden/Undocumented Options:");
      TIO.Put_Line ("----------------------------");
      for Opt of Hidden_Options loop
         TIO.Put_Line ("  " & Opt.Name.all);
         TIO.Put_Line ("    " & Opt.Description.all);
         TIO.Put_Line ("    Type: " & Opt.Value_Type.all &
                       " | Since: nano " & Opt.Nano_Version.all);
         TIO.New_Line;
      end loop;
   end List_All_Options;

   ---------------------------------------------------------------------------
   function Get_Categories return Category_Array is
   begin
      return Categories;
   end Get_Categories;

   ---------------------------------------------------------------------------
   function Category_Count return Natural is
   begin
      return Categories'Length;
   end Category_Count;

   ---------------------------------------------------------------------------
   function Get_Options_For_Category (Cat_Index : Natural) return Option_Array is
   begin
      --  Return hidden options for the Hidden category
      if Cat_Index = 8 then
         return Hidden_Options;
      end if;
      --  Placeholder for other categories
      return Hidden_Options (0 .. 0);
   end Get_Options_For_Category;

   ---------------------------------------------------------------------------
   function Get_Option (Cat_Index, Opt_Index : Natural) return Option_Record is
   begin
      if Cat_Index = 8 and Opt_Index <= Hidden_Options'Last then
         return Hidden_Options (Opt_Index);
      end if;
      return Hidden_Options (0);
   end Get_Option;

   ---------------------------------------------------------------------------
   function Option_Count (Cat_Index : Natural) return Natural is
   begin
      if Cat_Index <= Categories'Last then
         return Categories (Cat_Index).Option_Count;
      end if;
      return 0;
   end Option_Count;

   ---------------------------------------------------------------------------
   procedure Search (Query : String) is
      Lower_Query : constant String :=
        Ada.Characters.Handling.To_Lower (Query);
   begin
      Search_Result_Count := 0;
      for Opt of Hidden_Options loop
         if Ada.Strings.Fixed.Index
           (Ada.Characters.Handling.To_Lower (Opt.Name.all), Lower_Query) > 0
         then
            Search_Result_Count := Search_Result_Count + 1;
         end if;
      end loop;
   end Search;

   ---------------------------------------------------------------------------
   function Search_Results_Count return Natural is
   begin
      return Search_Result_Count;
   end Search_Results_Count;

   ---------------------------------------------------------------------------
   procedure Set_Option_Value (Cat_Index, Opt_Index : Natural; Value : String) is
   begin
      --  TODO: Implement value modification
      null;
   end Set_Option_Value;

   ---------------------------------------------------------------------------
   procedure Reset_Option (Cat_Index, Opt_Index : Natural) is
   begin
      --  TODO: Reset to default
      null;
   end Reset_Option;

   ---------------------------------------------------------------------------
   procedure Reset_All is
   begin
      --  TODO: Reset all options
      null;
   end Reset_All;

end Nano_Aider.Options;
