--  POSIX Symbolic Link Bindings - Implementation
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

package body Pathroot_TUI.Core.POSIX_Links is

   -------------------
   -- Read_Symlink --
   -------------------

   function Read_Symlink (Path : String; Buffer : out String) return Natural is
      C_Path   : constant char_array := To_C (Path);
      C_Buffer : char_array (0 .. Buffer'Length) := [others => nul];
      pragma Warnings (Off, C_Buffer);  --  Modified by C function
      Result   : int;
   begin
      Result := C_Readlink (C_Path, C_Buffer, C_Buffer'Length);

      if Result < 0 then
         return 0;  --  Error
      end if;

      declare
         Bytes_Read : constant Natural := Natural (Result);
         Target_Str : constant String := To_Ada (C_Buffer, Trim_Nul => False);
      begin
         if Bytes_Read <= Buffer'Length then
            Buffer (Buffer'First .. Buffer'First + Bytes_Read - 1) :=
              Target_Str (Target_Str'First .. Target_Str'First + Bytes_Read - 1);
            return Bytes_Read;
         else
            return 0;  --  Buffer too small
         end if;
      end;
   exception
      when others =>
         return 0;
   end Read_Symlink;

   ---------------------
   -- Create_Symlink --
   ---------------------

   function Create_Symlink (Target : String; Link_Path : String) return Boolean is
      C_Target   : constant char_array := To_C (Target);
      C_Linkpath : constant char_array := To_C (Link_Path);
      Result     : int;
   begin
      Result := C_Symlink (C_Target, C_Linkpath);
      return Result = 0;
   exception
      when others =>
         return False;
   end Create_Symlink;

end Pathroot_TUI.Core.POSIX_Links;
