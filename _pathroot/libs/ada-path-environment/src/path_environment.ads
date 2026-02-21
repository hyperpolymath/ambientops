--  Path_Environment - Cross-platform PATH environment management for Ada
--
--  This library provides a high-level interface for manipulating the PATH
--  environment variable across Windows and POSIX platforms.
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package Path_Environment is

   --  Path entry vector type
   package Path_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Unbounded_String);

   --  Path entry with validity information
   type Path_Entry is record
      Path     : Unbounded_String := Null_Unbounded_String;
      Is_Valid : Boolean := False;  --  True if directory exists
   end record;

   --  Path entry vector with validity
   package Path_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Path_Entry);

   --  PATH modification result
   type Path_Result is record
      Success   : Boolean := False;
      Message   : Unbounded_String := Null_Unbounded_String;
      New_Path  : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Position for adding entries
   type Add_Position is (Prepend, Append);

   ---------------------------------------------------------------------------
   --  Platform Detection
   ---------------------------------------------------------------------------

   --  Get the PATH separator for current platform (';' on Windows, ':' on POSIX)
   function Path_Separator return Character;

   --  Check if running on Windows
   function Is_Windows return Boolean;

   ---------------------------------------------------------------------------
   --  PATH Query Operations
   ---------------------------------------------------------------------------

   --  Get current PATH as a single string
   function Get_Path_String return String;

   --  Get current PATH as a list of entries
   function Get_Path_Entries return Path_Vectors.Vector;

   --  Get current PATH with validity flags for each entry
   function Get_Path_Entries_With_Validity return Path_Entry_Vectors.Vector;

   --  Check if a path entry exists in PATH
   function Path_Contains (Entry_Path : String) return Boolean;

   --  Validate that a path entry is a valid directory
   function Is_Valid_Path_Entry (Entry_Path : String) return Boolean;

   --  Count total entries in PATH
   function Path_Entry_Count return Natural;

   --  Count valid (existing directory) entries in PATH
   function Valid_Entry_Count return Natural;

   ---------------------------------------------------------------------------
   --  PATH Modification Operations
   ---------------------------------------------------------------------------

   --  Add a path entry to PATH
   --  Position defaults to Append (add at end)
   function Add_To_Path
     (Entry_Path : String;
      Position   : Add_Position := Append) return Path_Result;

   --  Remove a path entry from PATH
   function Remove_From_Path (Entry_Path : String) return Path_Result;

   --  Remove all invalid (non-existent directory) entries from PATH
   function Clean_Invalid_Entries return Path_Result;

   --  Remove duplicate entries from PATH (keeps first occurrence)
   function Remove_Duplicates return Path_Result;

   ---------------------------------------------------------------------------
   --  Executable Search
   ---------------------------------------------------------------------------

   --  Find an executable in PATH
   --  Returns full path if found, empty string if not
   function Find_Executable (Name : String) return String;

   --  Check if an executable exists in PATH
   function Executable_Exists (Name : String) return Boolean;

   ---------------------------------------------------------------------------
   --  Utility Functions
   ---------------------------------------------------------------------------

   --  Convert path result to JSON string
   function Result_To_JSON (Result : Path_Result) return String;

   --  Get PATH summary as JSON
   function Path_Summary_JSON return String;

end Path_Environment;
