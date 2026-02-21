--  _pathroot TUI - Envbase Module Specification
--  Handles _envbase JSON parsing and manipulation
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Pathroot_TUI.Core.Envbase is

   --  Environment information record
   type Environment_Info is record
      Env       : Unbounded_String := To_Unbounded_String ("unknown");
      Profile   : Unbounded_String := To_Unbounded_String ("default");
      Platform  : Unbounded_String := To_Unbounded_String ("unknown");
      Version   : Unbounded_String := Null_Unbounded_String;
      Created   : Unbounded_String := Null_Unbounded_String;
      Is_Valid  : Boolean := False;
   end record;

   --  Load environment info from _envbase file
   function Load_Environment (Devtools_Root : String) return Environment_Info;

   --  Save environment info to _envbase file
   procedure Save_Environment
     (Devtools_Root : String;
      Info          : Environment_Info);

   --  Switch to a different profile
   procedure Switch_Profile
     (Devtools_Root : String;
      Profile_Name  : String);

   --  Check if _envbase file exists
   function Envbase_Exists (Devtools_Root : String) return Boolean;

   --  Get the full path to _envbase
   function Envbase_Path (Devtools_Root : String) return String;

end Pathroot_TUI.Core.Envbase;
