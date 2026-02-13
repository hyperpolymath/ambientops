--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

with Ada.Directories;
with Ada.Calendar;
with Ada.Strings;
with Ada.Strings.Fixed;

with TotalUpdate.Logging;

package body TotalUpdate.Watcher is

   use TotalUpdate.Logging;

   --  Maximum number of watched paths
   Max_Paths : constant := 50;

   type Path_Entry is record
      Path    : String (1 .. 256);
      Length  : Natural := 0;
      Mtime   : Ada.Calendar.Time;
      Active  : Boolean := False;
   end record;

   type Path_Array is array (1 .. Max_Paths) of Path_Entry;

   --  Watch paths for common package managers
   APT_Paths : constant array (1 .. 2) of String (1 .. 30) :=
     ("/var/lib/dpkg/status         ",
      "/var/lib/apt/lists           ");

   DNF_Paths : constant array (1 .. 2) of String (1 .. 20) :=
     ("/var/lib/dnf        ",
      "/var/cache/dnf      ");

   Guix_Paths : constant array (1 .. 1) of String (1 .. 25) :=
     ("/var/guix/profiles         ");

   Nix_Paths : constant array (1 .. 1) of String (1 .. 25) :=
     ("/nix/var/nix/profiles      ");

   --  State
   Watched      : Path_Array;
   Path_Count   : Natural := 0;
   Has_Changes  : Boolean := False;
   Initialized_Flag : Boolean := False;

   function Get_Mtime (Path : String) return Ada.Calendar.Time is
      use Ada.Directories;
   begin
      if Exists (Path) then
         return Modification_Time (Path);
      else
         return Ada.Calendar.Clock;
      end if;
   exception
      when others =>
         return Ada.Calendar.Clock;
   end Get_Mtime;

   procedure Add_Watch_Path (Path : String) is
      use Ada.Directories;
   begin
      if Path_Count >= Max_Paths then
         Warning ("Maximum watch paths reached");
         return;
      end if;

      --  Trim trailing spaces
      declare
         Trimmed : constant String := Ada.Strings.Fixed.Trim (Path, Ada.Strings.Both);
      begin
         if Exists (Trimmed) then
            Path_Count := Path_Count + 1;
            Watched (Path_Count).Path (1 .. Trimmed'Length) := Trimmed;
            Watched (Path_Count).Length := Trimmed'Length;
            Watched (Path_Count).Mtime := Get_Mtime (Trimmed);
            Watched (Path_Count).Active := True;
            Debug ("Watching: " & Trimmed);
         end if;
      end;
   end Add_Watch_Path;

   procedure Initialize is
      use Ada.Directories;
   begin
      Info ("Initializing file watcher");

      --  Detect and watch package manager databases
      --  APT (Debian/Ubuntu)
      if Exists ("/var/lib/dpkg") then
         for Path of APT_Paths loop
            Add_Watch_Path (Path);
         end loop;
      end if;

      --  DNF (Fedora/RHEL)
      if Exists ("/var/lib/dnf") then
         for Path of DNF_Paths loop
            Add_Watch_Path (Path);
         end loop;
      end if;

      --  Guix
      if Exists ("/var/guix") then
         for Path of Guix_Paths loop
            Add_Watch_Path (Path);
         end loop;
      end if;

      --  Nix
      if Exists ("/nix") then
         for Path of Nix_Paths loop
            Add_Watch_Path (Path);
         end loop;
      end if;

      Info ("Watcher initialized, monitoring " &
            Natural'Image (Path_Count) & " paths");
      Initialized_Flag := True;
   end Initialize;

   procedure Process is
      use Ada.Calendar;
   begin
      if not Initialized_Flag then
         return;
      end if;

      --  Check each watched path for changes
      for I in 1 .. Path_Count loop
         if Watched (I).Active then
            declare
               Path : constant String :=
                 Watched (I).Path (1 .. Watched (I).Length);
               New_Mtime : constant Time := Get_Mtime (Path);
            begin
               if New_Mtime /= Watched (I).Mtime then
                  Info ("Change detected: " & Path);
                  Watched (I).Mtime := New_Mtime;
                  Has_Changes := True;
               end if;
            end;
         end if;
      end loop;
   end Process;

   procedure Shutdown is
   begin
      Info ("Watcher shutting down");
      Initialized_Flag := False;
      Path_Count := 0;
      Has_Changes := False;
   end Shutdown;

   procedure Watch (Path : String) is
   begin
      Add_Watch_Path (Path);
   end Watch;

   procedure Unwatch (Path : String) is
   begin
      for I in 1 .. Path_Count loop
         if Watched (I).Active and then
           Watched (I).Path (1 .. Watched (I).Length) = Path
         then
            Watched (I).Active := False;
            Debug ("Stopped watching: " & Path);
            return;
         end if;
      end loop;
   end Unwatch;

   function Changes_Detected return Boolean is
   begin
      return Has_Changes;
   end Changes_Detected;

   procedure Clear_Changes is
   begin
      Has_Changes := False;
   end Clear_Changes;

   function Watched_Path_Count return Natural is
      Count : Natural := 0;
   begin
      for I in 1 .. Path_Count loop
         if Watched (I).Active then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Watched_Path_Count;

end TotalUpdate.Watcher;
