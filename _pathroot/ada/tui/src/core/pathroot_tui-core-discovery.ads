--  _pathroot TUI - Discovery Module Specification
--  Handles _pathroot file discovery across platforms
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Pathroot_TUI.Core.Discovery is

   --  Search locations for _pathroot file
   type Search_Location is
     (Loc_Windows_Root,    --  C:\_pathroot
      Loc_WSL_Mount,       --  /mnt/c/_pathroot
      Loc_Posix_Root,      --  /_pathroot
      Loc_Home);           --  ~/.pathroot

   --  Discover the _pathroot file and devtools root
   --  Returns True if found, with Pathroot_File and Devtools_Root set
   function Discover_Pathroot
     (Pathroot_File : out Unbounded_String;
      Devtools_Root : out Unbounded_String) return Boolean;

   --  Check if a specific path contains a valid _pathroot file
   function Is_Valid_Pathroot (Path : String) return Boolean;

   --  Read the devtools root from a _pathroot file
   function Read_Devtools_Root (Pathroot_Path : String) return String;

   --  Determine current platform
   type Platform_Type is (Platform_Windows, Platform_WSL, Platform_Linux, Platform_Darwin);
   function Current_Platform return Platform_Type;

end Pathroot_TUI.Core.Discovery;
