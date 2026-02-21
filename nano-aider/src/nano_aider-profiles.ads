-------------------------------------------------------------------------------
--  nano-aider - Configuration Profiles
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

package Nano_Aider.Profiles is

   --  Built-in profile types
   type Profile_Type is
     (Profile_Minimal,        -- Bare essentials, no extras
      Profile_Default,        -- Standard nano defaults
      Profile_Developer,      -- Optimized for coding
      Profile_Writer,         -- Optimized for prose writing
      Profile_Power_User,     -- All hidden options enabled
      Profile_Vim_Like,       -- Vim-style keybindings
      Profile_Emacs_Like,     -- Emacs-style keybindings
      Profile_Custom);        -- User-defined profile

   --  Profile record
   type Profile_Record is record
      Name        : access constant String;
      Description : access constant String;
      Is_Builtin  : Boolean;
      File_Path   : access constant String;
   end record;

   type Profile_Array is array (Natural range <>) of Profile_Record;

   --  Profile operations
   procedure Load_Profile (Profile : Profile_Type);
   procedure Load_Profile_From_File (Path : String);
   procedure Save_Profile (Name : String; Path : String);

   --  Query profiles
   function Get_Builtin_Profiles return Profile_Array;
   function Get_User_Profiles return Profile_Array;
   function Get_Current_Profile return Profile_Type;
   function Get_Profile_Description (Profile : Profile_Type) return String;

   --  Profile management
   procedure Create_Profile (Name : String);
   procedure Delete_Profile (Name : String);
   procedure Rename_Profile (Old_Name, New_Name : String);

end Nano_Aider.Profiles;
