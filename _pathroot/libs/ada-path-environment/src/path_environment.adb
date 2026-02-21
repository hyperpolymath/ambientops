--  Path_Environment - Cross-platform PATH environment management for Ada
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;

package body Path_Environment is

   use Ada.Directories;
   use Ada.Strings.Fixed;

   --  Executable extensions for Windows
   Win_Extensions : constant array (1 .. 4) of String (1 .. 4) :=
     (".exe", ".cmd", ".bat", ".com");

   ----------------
   -- Is_Windows --
   ----------------

   function Is_Windows return Boolean is
   begin
      return Ada.Environment_Variables.Exists ("WINDIR") or
             Ada.Environment_Variables.Exists ("SystemRoot");
   end Is_Windows;

   --------------------
   -- Path_Separator --
   --------------------

   function Path_Separator return Character is
   begin
      if Is_Windows then
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

      loop
         Sep_Pos := Index (Path_Str (Start_Pos .. Path_Str'Last),
                           String'(1 => Sep));

         if Sep_Pos = 0 then
            if Start_Pos <= Path_Str'Last then
               Result.Append (To_Unbounded_String (
                 Path_Str (Start_Pos .. Path_Str'Last)));
            end if;
            exit;
         else
            if Sep_Pos > Start_Pos then
               Result.Append (To_Unbounded_String (
                 Path_Str (Start_Pos .. Sep_Pos - 1)));
            end if;
            Start_Pos := Sep_Pos + 1;

            if Start_Pos > Path_Str'Last then
               exit;
            end if;
         end if;
      end loop;

      return Result;
   end Get_Path_Entries;

   ----------------------------------
   -- Get_Path_Entries_With_Validity --
   ----------------------------------

   function Get_Path_Entries_With_Validity return Path_Entry_Vectors.Vector is
      Result  : Path_Entry_Vectors.Vector;
      Entries : constant Path_Vectors.Vector := Get_Path_Entries;
   begin
      for E of Entries loop
         Result.Append ((
           Path     => E,
           Is_Valid => Is_Valid_Path_Entry (To_String (E))
         ));
      end loop;
      return Result;
   end Get_Path_Entries_With_Validity;

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

   ----------------------
   -- Path_Entry_Count --
   ----------------------

   function Path_Entry_Count return Natural is
   begin
      return Natural (Get_Path_Entries.Length);
   end Path_Entry_Count;

   -----------------------
   -- Valid_Entry_Count --
   -----------------------

   function Valid_Entry_Count return Natural is
      Count   : Natural := 0;
      Entries : constant Path_Vectors.Vector := Get_Path_Entries;
   begin
      for E of Entries loop
         if Is_Valid_Path_Entry (To_String (E)) then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Valid_Entry_Count;

   -----------------
   -- Add_To_Path --
   -----------------

   function Add_To_Path
     (Entry_Path : String;
      Position   : Add_Position := Append) return Path_Result
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
      case Position is
         when Prepend =>
            if Old_Path'Length > 0 then
               New_Path := To_Unbounded_String (Entry_Path & Sep & Old_Path);
            else
               New_Path := To_Unbounded_String (Entry_Path);
            end if;
         when Append =>
            if Old_Path'Length > 0 then
               New_Path := To_Unbounded_String (Old_Path & Sep & Entry_Path);
            else
               New_Path := To_Unbounded_String (Entry_Path);
            end if;
      end case;

      --  Set the new PATH
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

   ---------------------------
   -- Clean_Invalid_Entries --
   ---------------------------

   function Clean_Invalid_Entries return Path_Result is
      Result        : Path_Result;
      Sep           : constant Character := Path_Separator;
      Entries       : constant Path_Vectors.Vector := Get_Path_Entries;
      New_Path      : Unbounded_String := Null_Unbounded_String;
      First         : Boolean := True;
      Removed_Count : Natural := 0;
   begin
      for E of Entries loop
         if Is_Valid_Path_Entry (To_String (E)) then
            if First then
               New_Path := E;
               First := False;
            else
               Append (New_Path, Sep & To_String (E));
            end if;
         else
            Removed_Count := Removed_Count + 1;
         end if;
      end loop;

      Ada.Environment_Variables.Set ("PATH", To_String (New_Path));

      Result.Success := True;
      Result.Message := To_Unbounded_String (
        "Removed" & Natural'Image (Removed_Count) & " invalid entries");
      Result.New_Path := New_Path;
      return Result;
   exception
      when others =>
         Result.Success := False;
         Result.Message := To_Unbounded_String ("Failed to clean PATH");
         return Result;
   end Clean_Invalid_Entries;

   -----------------------
   -- Remove_Duplicates --
   -----------------------

   function Remove_Duplicates return Path_Result is
      Result        : Path_Result;
      Sep           : constant Character := Path_Separator;
      Entries       : constant Path_Vectors.Vector := Get_Path_Entries;
      New_Path      : Unbounded_String := Null_Unbounded_String;
      Seen          : Path_Vectors.Vector;
      First         : Boolean := True;
      Removed_Count : Natural := 0;

      function Already_Seen (Path : Unbounded_String) return Boolean is
      begin
         for S of Seen loop
            if S = Path then
               return True;
            end if;
         end loop;
         return False;
      end Already_Seen;

   begin
      for E of Entries loop
         if Already_Seen (E) then
            Removed_Count := Removed_Count + 1;
         else
            Seen.Append (E);
            if First then
               New_Path := E;
               First := False;
            else
               Append (New_Path, Sep & To_String (E));
            end if;
         end if;
      end loop;

      Ada.Environment_Variables.Set ("PATH", To_String (New_Path));

      Result.Success := True;
      Result.Message := To_Unbounded_String (
        "Removed" & Natural'Image (Removed_Count) & " duplicate entries");
      Result.New_Path := New_Path;
      return Result;
   exception
      when others =>
         Result.Success := False;
         Result.Message := To_Unbounded_String ("Failed to deduplicate PATH");
         return Result;
   end Remove_Duplicates;

   ---------------------
   -- Find_Executable --
   ---------------------

   function Find_Executable (Name : String) return String is
      Entries : constant Path_Vectors.Vector := Get_Path_Entries;
   begin
      for E of Entries loop
         declare
            Dir : constant String := To_String (E);
         begin
            if Is_Windows then
               --  Try with common extensions on Windows
               for Ext of Win_Extensions loop
                  declare
                     Full_Path : constant String := Dir & "/" & Name & Ext;
                  begin
                     if Exists (Full_Path) and then Kind (Full_Path) = Ordinary_File then
                        return Full_Path;
                     end if;
                  end;
               end loop;
               --  Also try without extension
               declare
                  Full_Path : constant String := Dir & "/" & Name;
               begin
                  if Exists (Full_Path) and then Kind (Full_Path) = Ordinary_File then
                     return Full_Path;
                  end if;
               end;
            else
               --  POSIX: check file exists and is executable
               declare
                  Full_Path : constant String := Dir & "/" & Name;
               begin
                  if Exists (Full_Path) and then Kind (Full_Path) = Ordinary_File then
                     if GNAT.OS_Lib.Is_Executable_File (Full_Path) then
                        return Full_Path;
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;

      return "";
   exception
      when others =>
         return "";
   end Find_Executable;

   -----------------------
   -- Executable_Exists --
   -----------------------

   function Executable_Exists (Name : String) return Boolean is
   begin
      return Find_Executable (Name) /= "";
   end Executable_Exists;

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

   -----------------------
   -- Path_Summary_JSON --
   -----------------------

   function Path_Summary_JSON return String is
      function Img (N : Natural) return String is
         S : constant String := Natural'Image (N);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;

      Total : constant Natural := Path_Entry_Count;
      Valid : constant Natural := Valid_Entry_Count;
   begin
      return "{" &
        """total_entries"": " & Img (Total) & ", " &
        """valid_entries"": " & Img (Valid) & ", " &
        """invalid_entries"": " & Img (Total - Valid) & ", " &
        """separator"": """ & Path_Separator & """" &
        "}";
   end Path_Summary_JSON;

end Path_Environment;
