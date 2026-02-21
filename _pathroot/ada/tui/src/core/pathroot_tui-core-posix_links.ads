--  POSIX Symbolic Link Bindings
--  Thin bindings to POSIX readlink/symlink functions
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Interfaces.C; use Interfaces.C;

package Pathroot_TUI.Core.POSIX_Links is

   --  Read symbolic link target
   --  Returns number of bytes read, or -1 on error
   function C_Readlink
     (Path   : char_array;
      Buffer : char_array;
      Bufsize : size_t) return int
   with Import, Convention => C, External_Name => "readlink";

   --  Create symbolic link
   --  Returns 0 on success, -1 on error
   function C_Symlink
     (Target : char_array;
      Linkpath : char_array) return int
   with Import, Convention => C, External_Name => "symlink";

   --  Ada-friendly wrappers
   function Read_Symlink (Path : String; Buffer : out String) return Natural;
   --  Returns number of characters read into Buffer

   function Create_Symlink (Target : String; Link_Path : String) return Boolean;
   --  Returns True on success

end Pathroot_TUI.Core.POSIX_Links;
