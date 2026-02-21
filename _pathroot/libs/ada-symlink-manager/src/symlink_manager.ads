--  Symlink_Manager - Cross-platform symbolic link management for Ada
--
--  This library provides a high-level interface for creating, auditing,
--  and managing symbolic links across Windows and POSIX platforms.
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Symlink_Manager is

   --  Link status enumeration
   type Link_Status is
     (Link_Valid,       --  Link exists and points to valid target
      Link_Broken,      --  Link exists but target is missing
      Link_Missing,     --  Link does not exist
      Link_Not_Link,    --  Path exists but is not a symbolic link
      Link_Error);      --  Error checking link status

   --  Link information record
   type Link_Info is record
      Link_Path    : Unbounded_String := Null_Unbounded_String;
      Target_Path  : Unbounded_String := Null_Unbounded_String;
      Status       : Link_Status := Link_Missing;
      Error_Msg    : Unbounded_String := Null_Unbounded_String;
   end record;

   --  Audit result record for bulk operations
   type Audit_Result is record
      Total_Links   : Natural := 0;
      Valid_Links   : Natural := 0;
      Broken_Links  : Natural := 0;
      Missing_Links : Natural := 0;
      Errors        : Natural := 0;
   end record;

   --  Maximum path length constant
   Max_Path_Length : constant := 4096;

   ---------------------------------------------------------------------------
   --  Core Operations
   ---------------------------------------------------------------------------

   --  Create a symbolic link
   --  Returns True on success, False on failure with error message set
   function Create_Link
     (Link_Path   : String;
      Target_Path : String;
      Error_Msg   : out Unbounded_String) return Boolean;

   --  Remove a symbolic link (only if it is actually a symlink)
   --  Returns True on success, False if path doesn't exist or isn't a link
   function Remove_Link
     (Link_Path : String;
      Error_Msg : out Unbounded_String) return Boolean;

   --  Check if a path is a symbolic link
   function Is_Symbolic_Link (Path : String) return Boolean;

   --  Get link target path
   --  Returns empty string if not a link or on error
   function Get_Link_Target (Link_Path : String) return String;

   --  Check detailed status of a single link
   function Check_Link_Status (Link_Path : String) return Link_Info;

   ---------------------------------------------------------------------------
   --  Bulk Operations
   ---------------------------------------------------------------------------

   --  Audit all symbolic links in a directory
   --  Set Recursive to True to scan subdirectories
   function Audit_Directory
     (Directory_Path : String;
      Recursive      : Boolean := False) return Audit_Result;

   ---------------------------------------------------------------------------
   --  Utility Functions
   ---------------------------------------------------------------------------

   --  Convert link status to string representation
   function Status_To_String (Status : Link_Status) return String;

   --  Convert audit result to JSON string
   function Audit_To_JSON (Result : Audit_Result) return String;

   --  Convert link info to JSON string
   function Link_Info_To_JSON (Info : Link_Info) return String;

end Symlink_Manager;
