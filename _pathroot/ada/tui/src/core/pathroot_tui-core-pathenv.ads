--  _pathroot TUI - PATH Environment Module Specification
--  Handles PATH environment variable operations
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package Pathroot_TUI.Core.Pathenv is

   --  Path entry vector type
   package Path_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Unbounded_String);

   --  PATH modification result
   type Path_Result is record
      Success   : Boolean := False;
      Message   : Unbounded_String := Null_Unbounded_String;
      New_Path  : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Get current PATH as a list of entries
   function Get_Path_Entries return Path_Vectors.Vector;

   --  Get the PATH separator for current platform
   function Path_Separator return Character;

   --  Check if a path entry exists in PATH
   function Path_Contains (Entry_Path : String) return Boolean;

   --  Validate that a path entry is a valid directory
   function Is_Valid_Path_Entry (Entry_Path : String) return Boolean;

   --  Add a path entry to PATH
   --  Position can be "prepend" or "append"
   function Add_To_Path
     (Entry_Path : String;
      Position   : String := "append") return Path_Result;

   --  Remove a path entry from PATH
   function Remove_From_Path (Entry_Path : String) return Path_Result;

   --  Get PATH as a single string
   function Get_Path_String return String;

   --  Convert path result to JSON string
   function Result_To_JSON (Result : Path_Result) return String;

end Pathroot_TUI.Core.Pathenv;
