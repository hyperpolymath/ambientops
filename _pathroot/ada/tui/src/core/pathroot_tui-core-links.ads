--  _pathroot TUI - Symbolic Links Module Specification
--  Handles symbolic link creation and auditing
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Pathroot_TUI.Core.Links is

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

   --  Audit result record
   type Audit_Result is record
      Total_Links   : Natural := 0;
      Valid_Links   : Natural := 0;
      Broken_Links  : Natural := 0;
      Missing_Links : Natural := 0;
      Errors        : Natural := 0;
   end record;

   --  Create a symbolic link
   --  Returns True on success, False on failure with error message set
   function Create_Link
     (Link_Path   : String;
      Target_Path : String;
      Error_Msg   : out Unbounded_String) return Boolean;

   --  Check if a path is a symbolic link
   function Is_Symbolic_Link (Path : String) return Boolean;

   --  Get link target
   function Get_Link_Target (Link_Path : String) return String;

   --  Check status of a single link
   function Check_Link_Status (Link_Path : String) return Link_Info;

   --  Audit all links in devtools bin directory
   function Audit_Links (Devtools_Root : String) return Audit_Result;

   --  Convert link status to string
   function Status_To_String (Status : Link_Status) return String;

   --  Convert audit result to JSON string
   function Audit_To_JSON (Result : Audit_Result) return String;

end Pathroot_TUI.Core.Links;
