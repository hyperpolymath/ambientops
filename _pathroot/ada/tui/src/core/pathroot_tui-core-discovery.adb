--  _pathroot TUI - Discovery Module Body
--  Handles _pathroot file discovery across platforms
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Directories;
with Ada.Text_IO;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;

package body Pathroot_TUI.Core.Discovery is

   use Ada.Directories;
   use Ada.Text_IO;

   --  Platform-specific search paths
   Windows_Paths : constant array (Positive range <>) of String (1 .. 12) :=
     ("C:\_pathroot", "D:\_pathroot");

   Posix_Paths : constant array (Positive range <>) of access constant String :=
     (new String'("/_pathroot"),
      new String'("/mnt/c/_pathroot"),
      new String'("/mnt/d/_pathroot"));

   ----------------------
   -- Current_Platform --
   ----------------------

   function Current_Platform return Platform_Type is
   begin
      --  Check for Windows
      if Ada.Environment_Variables.Exists ("WINDIR") or
         Ada.Environment_Variables.Exists ("SystemRoot")
      then
         return Platform_Windows;
      end if;

      --  Check for WSL
      if Exists ("/proc/version") then
         declare
            File : File_Type;
            Line : String (1 .. 256);
            Last : Natural;
         begin
            Open (File, In_File, "/proc/version");
            Get_Line (File, Line, Last);
            Close (File);

            if Ada.Strings.Fixed.Index (Line (1 .. Last), "Microsoft") > 0 or
               Ada.Strings.Fixed.Index (Line (1 .. Last), "WSL") > 0
            then
               return Platform_WSL;
            end if;
         exception
            when others =>
               null;
         end;
      end if;

      --  Check for Darwin (macOS)
      if Exists ("/System/Library") then
         return Platform_Darwin;
      end if;

      --  Default to Linux
      return Platform_Linux;
   end Current_Platform;

   ----------------------
   -- Is_Valid_Pathroot --
   ----------------------

   function Is_Valid_Pathroot (Path : String) return Boolean is
   begin
      if not Exists (Path) then
         return False;
      end if;

      if Kind (Path) /= Ordinary_File then
         return False;
      end if;

      --  Check file is readable and non-empty
      declare
         File : File_Type;
         Line : String (1 .. Max_Path_Length);
         Last : Natural;
      begin
         Open (File, In_File, Path);
         Get_Line (File, Line, Last);
         Close (File);
         return Last > 0;
      exception
         when others =>
            return False;
      end;
   end Is_Valid_Pathroot;

   -----------------------
   -- Read_Devtools_Root --
   -----------------------

   function Read_Devtools_Root (Pathroot_Path : String) return String is
      File : File_Type;
      Line : String (1 .. Max_Path_Length);
      Last : Natural;
   begin
      Open (File, In_File, Pathroot_Path);
      Get_Line (File, Line, Last);
      Close (File);

      --  Trim trailing whitespace and carriage returns
      while Last > 0 and then
        (Line (Last) = ' ' or Line (Last) = ASCII.CR or Line (Last) = ASCII.LF)
      loop
         Last := Last - 1;
      end loop;

      return Line (1 .. Last);
   exception
      when others =>
         return "";
   end Read_Devtools_Root;

   -----------------------
   -- Discover_Pathroot --
   -----------------------

   function Discover_Pathroot
     (Pathroot_File : out Unbounded_String;
      Devtools_Root : out Unbounded_String) return Boolean
   is
      Platform : constant Platform_Type := Current_Platform;
   begin
      Pathroot_File := Null_Unbounded_String;
      Devtools_Root := Null_Unbounded_String;

      case Platform is
         when Platform_Windows =>
            --  Try Windows paths
            for Path of Windows_Paths loop
               if Is_Valid_Pathroot (Path) then
                  Pathroot_File := To_Unbounded_String (Path);
                  Devtools_Root := To_Unbounded_String (Read_Devtools_Root (Path));
                  return True;
               end if;
            end loop;

         when Platform_WSL | Platform_Linux | Platform_Darwin =>
            --  Try POSIX paths
            for Path of Posix_Paths loop
               if Is_Valid_Pathroot (Path.all) then
                  Pathroot_File := To_Unbounded_String (Path.all);
                  Devtools_Root := To_Unbounded_String (Read_Devtools_Root (Path.all));
                  return True;
               end if;
            end loop;

            --  Try home directory fallback
            if Ada.Environment_Variables.Exists ("HOME") then
               declare
                  Home_Path : constant String :=
                    Ada.Environment_Variables.Value ("HOME") & "/.pathroot";
               begin
                  if Is_Valid_Pathroot (Home_Path) then
                     Pathroot_File := To_Unbounded_String (Home_Path);
                     Devtools_Root := To_Unbounded_String (Read_Devtools_Root (Home_Path));
                     return True;
                  end if;
               end;
            end if;
      end case;

      return False;
   end Discover_Pathroot;

end Pathroot_TUI.Core.Discovery;
