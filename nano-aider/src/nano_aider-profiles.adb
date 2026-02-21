-------------------------------------------------------------------------------
--  nano-aider - Configuration Profiles (Body)
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

package body Nano_Aider.Profiles is

   --  Profile names and descriptions
   Name_Minimal    : aliased constant String := "Minimal";
   Name_Default    : aliased constant String := "Default";
   Name_Developer  : aliased constant String := "Developer";
   Name_Writer     : aliased constant String := "Writer";
   Name_Power      : aliased constant String := "Power User";
   Name_Vim        : aliased constant String := "Vim-Like";
   Name_Emacs      : aliased constant String := "Emacs-Like";

   Desc_Minimal   : aliased constant String :=
     "Bare essentials only. No syntax highlighting, minimal interface.";
   Desc_Default   : aliased constant String :=
     "Standard nano defaults. Familiar to most users.";
   Desc_Developer : aliased constant String :=
     "Optimized for coding. Line numbers, syntax highlighting, auto-indent.";
   Desc_Writer    : aliased constant String :=
     "Optimized for prose. Soft wrapping, spell checking, guide stripe.";
   Desc_Power     : aliased constant String :=
     "All hidden options exposed and enabled. Maximum functionality.";
   Desc_Vim       : aliased constant String :=
     "Vim-style keybindings. Modal editing emulation.";
   Desc_Emacs     : aliased constant String :=
     "Emacs-style keybindings. Control and Meta key combinations.";

   Empty_Path : aliased constant String := "";

   Builtin_Profiles : constant Profile_Array (0 .. 6) :=
     ((Name_Minimal'Access,   Desc_Minimal'Access,   True, Empty_Path'Access),
      (Name_Default'Access,   Desc_Default'Access,   True, Empty_Path'Access),
      (Name_Developer'Access, Desc_Developer'Access, True, Empty_Path'Access),
      (Name_Writer'Access,    Desc_Writer'Access,    True, Empty_Path'Access),
      (Name_Power'Access,     Desc_Power'Access,     True, Empty_Path'Access),
      (Name_Vim'Access,       Desc_Vim'Access,       True, Empty_Path'Access),
      (Name_Emacs'Access,     Desc_Emacs'Access,     True, Empty_Path'Access));

   Current_Profile : Profile_Type := Profile_Default;

   ---------------------------------------------------------------------------
   procedure Load_Profile (Profile : Profile_Type) is
   begin
      Current_Profile := Profile;

      case Profile is
         when Profile_Minimal =>
            --  Disable most options
            null;
         when Profile_Default =>
            --  Use nano defaults
            null;
         when Profile_Developer =>
            --  Enable: linenumbers, autoindent, syntax highlighting
            --  Enable: tabstospaces, matchbrackets, smarthome
            null;
         when Profile_Writer =>
            --  Enable: softwrap, atblanks, guidestripe 80
            --  Enable: speller, punct
            null;
         when Profile_Power_User =>
            --  Enable all hidden options
            null;
         when Profile_Vim_Like =>
            --  Set vim-style keybindings
            null;
         when Profile_Emacs_Like =>
            --  Set emacs-style keybindings
            null;
         when Profile_Custom =>
            --  Load from user file
            null;
      end case;
   end Load_Profile;

   ---------------------------------------------------------------------------
   procedure Load_Profile_From_File (Path : String) is
   begin
      --  TODO: Parse profile file
      Current_Profile := Profile_Custom;
   end Load_Profile_From_File;

   ---------------------------------------------------------------------------
   procedure Save_Profile (Name : String; Path : String) is
   begin
      --  TODO: Save current settings as named profile
      null;
   end Save_Profile;

   ---------------------------------------------------------------------------
   function Get_Builtin_Profiles return Profile_Array is
   begin
      return Builtin_Profiles;
   end Get_Builtin_Profiles;

   ---------------------------------------------------------------------------
   function Get_User_Profiles return Profile_Array is
   begin
      --  TODO: Scan user profile directory
      return Builtin_Profiles (0 .. 0);  -- Placeholder
   end Get_User_Profiles;

   ---------------------------------------------------------------------------
   function Get_Current_Profile return Profile_Type is
   begin
      return Current_Profile;
   end Get_Current_Profile;

   ---------------------------------------------------------------------------
   function Get_Profile_Description (Profile : Profile_Type) return String is
   begin
      case Profile is
         when Profile_Minimal    => return Desc_Minimal;
         when Profile_Default    => return Desc_Default;
         when Profile_Developer  => return Desc_Developer;
         when Profile_Writer     => return Desc_Writer;
         when Profile_Power_User => return Desc_Power;
         when Profile_Vim_Like   => return Desc_Vim;
         when Profile_Emacs_Like => return Desc_Emacs;
         when Profile_Custom     => return "Custom user profile";
      end case;
   end Get_Profile_Description;

   ---------------------------------------------------------------------------
   procedure Create_Profile (Name : String) is
   begin
      --  TODO: Create new user profile
      null;
   end Create_Profile;

   ---------------------------------------------------------------------------
   procedure Delete_Profile (Name : String) is
   begin
      --  TODO: Delete user profile
      null;
   end Delete_Profile;

   ---------------------------------------------------------------------------
   procedure Rename_Profile (Old_Name, New_Name : String) is
   begin
      --  TODO: Rename user profile
      null;
   end Rename_Profile;

end Nano_Aider.Profiles;
