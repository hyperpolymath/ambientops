--  _pathroot TUI - PATH Environment Module Body
--  Handles PATH environment variable operations
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;

package body Pathroot_TUI.Core.Pathenv is

   use Ada.Directories;
   use Ada.Strings.Fixed;

   --------------------
   -- Path_Separator --
   --------------------

   function Path_Separator return Character is
   begin
      --  Windows uses ; while POSIX uses :
      if Ada.Environment_Variables.Exists ("WINDIR") or
         Ada.Environment_Variables.Exists ("SystemRoot")
      then
         return ';';
      else
         return ':';
      end if;
   end Path_Separator;

   ---------------------
   -- Get_Path_String --
   ---------------------

   function Get_Path_String return String is
   begin
      if Ada.Environment_Variables.Exists ("PATH") then
         return Ada.Environment_Variables.Value ("PATH");
      else
         return "";
      end if;
   end Get_Path_String;

   ----------------------
   -- Get_Path_Entries --
   ----------------------

   function Get_Path_Entries return Path_Vectors.Vector is
      Result    : Path_Vectors.Vector;
      Path_Str  : constant String := Get_Path_String;
      Sep       : constant Character := Path_Separator;
      Start_Pos : Positive := Path_Str'First;
      Sep_Pos   : Natural;
   begin
      if Path_Str'Length = 0 then
         return Result;
      end if;

      --  Split PATH by separator
      loop
         Sep_Pos := Index (Path_Str (Start_Pos .. Path_Str'Last),
                           String'(1 => Sep));

         if Sep_Pos = 0 then
            --  Last entry (no more separators)
            if Start_Pos <= Path_Str'Last then
               Result.Append (To_Unbounded_String (
                 Path_Str (Start_Pos .. Path_Str'Last)));
            end if;
            exit;
         else
            --  Entry before separator
            if Sep_Pos > Start_Pos then
               Result.Append (To_Unbounded_String (
                 Path_Str (Start_Pos .. Sep_Pos - 1)));
            end if;
            Start_Pos := Sep_Pos + 1;

            --  Handle end of string
            if Start_Pos > Path_Str'Last then
               exit;
            end if;
         end if;
      end loop;

      return Result;
   end Get_Path_Entries;

   -------------------
   -- Path_Contains --
   -------------------

   function Path_Contains (Entry_Path : String) return Boolean is
      Entries : constant Path_Vectors.Vector := Get_Path_Entries;
   begin
      for E of Entries loop
         if To_String (E) = Entry_Path then
            return True;
         end if;
      end loop;
      return False;
   end Path_Contains;

   -------------------------
   -- Is_Valid_Path_Entry --
   -------------------------

   function Is_Valid_Path_Entry (Entry_Path : String) return Boolean is
   begin
      return Exists (Entry_Path) and then Kind (Entry_Path) = Directory;
   exception
      when others =>
         return False;
   end Is_Valid_Path_Entry;

   -----------------
   -- Add_To_Path --
   -----------------

   function Add_To_Path
     (Entry_Path : String;
      Position   : String := "append") return Path_Result
   is
      Result   : Path_Result;
      Sep      : constant Character := Path_Separator;
      Old_Path : constant String := Get_Path_String;
      New_Path : Unbounded_String;
   begin
      --  Check if path already exists
      if Path_Contains (Entry_Path) then
         Result.Success := True;
         Result.Message := To_Unbounded_String ("Path entry already exists");
         Result.New_Path := To_Unbounded_String (Old_Path);
         return Result;
      end if;

      --  Validate the path entry is a valid directory
      if not Is_Valid_Path_Entry (Entry_Path) then
         Result.Success := False;
         Result.Message := To_Unbounded_String (
           "Path entry is not a valid directory: " & Entry_Path);
         return Result;
      end if;

      --  Build new PATH
      if Position = "prepend" then
         if Old_Path'Length > 0 then
            New_Path := To_Unbounded_String (Entry_Path & Sep & Old_Path);
         else
            New_Path := To_Unbounded_String (Entry_Path);
         end if;
      else  --  append
         if Old_Path'Length > 0 then
            New_Path := To_Unbounded_String (Old_Path & Sep & Entry_Path);
         else
            New_Path := To_Unbounded_String (Entry_Path);
         end if;
      end if;

      --  Set the new PATH environment variable
      Ada.Environment_Variables.Set ("PATH", To_String (New_Path));

      Result.Success := True;
      Result.Message := To_Unbounded_String ("Path entry added successfully");
      Result.New_Path := New_Path;
      return Result;
   exception
      when others =>
         Result.Success := False;
         Result.Message := To_Unbounded_String ("Failed to modify PATH");
         return Result;
   end Add_To_Path;

   ----------------------
   -- Remove_From_Path --
   ----------------------

   function Remove_From_Path (Entry_Path : String) return Path_Result is
      Result   : Path_Result;
      Sep      : constant Character := Path_Separator;
      Entries  : constant Path_Vectors.Vector := Get_Path_Entries;
      New_Path : Unbounded_String := Null_Unbounded_String;
      Found    : Boolean := False;
      First    : Boolean := True;
   begin
      --  Build new PATH without the specified entry
      for E of Entries loop
         if To_String (E) = Entry_Path then
            Found := True;
         else
            if First then
               New_Path := E;
               First := False;
            else
               Append (New_Path, Sep & To_String (E));
            end if;
         end if;
      end loop;

      if not Found then
         Result.Success := False;
         Result.Message := To_Unbounded_String (
           "Path entry not found in PATH: " & Entry_Path);
         Result.New_Path := To_Unbounded_String (Get_Path_String);
         return Result;
      end if;

      --  Set the new PATH environment variable
      Ada.Environment_Variables.Set ("PATH", To_String (New_Path));

      Result.Success := True;
      Result.Message := To_Unbounded_String ("Path entry removed successfully");
      Result.New_Path := New_Path;
      return Result;
   exception
      when others =>
         Result.Success := False;
         Result.Message := To_Unbounded_String ("Failed to modify PATH");
         return Result;
   end Remove_From_Path;

   --------------------
   -- Result_To_JSON --
   --------------------

   function Result_To_JSON (Result : Path_Result) return String is
      Success_Str : constant String := (if Result.Success then "true" else "false");
   begin
      return "{" &
        """success"": " & Success_Str & ", " &
        """message"": """ & To_String (Result.Message) & """" &
        "}";
   end Result_To_JSON;

end Pathroot_TUI.Core.Pathenv;
