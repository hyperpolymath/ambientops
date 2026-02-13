--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Backend_Nix - Nix package manager backend implementation

pragma SPARK_Mode (Off);  --  Implementation uses shell commands

with Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Directories;
with GNAT.OS_Lib;

package body Backend_Nix is

   use Ada.Text_IO;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Helper Functions
   --  ═══════════════════════════════════════════════════════════════════════

   function Execute_Command
     (Command : String;
      Output  : out Unbounded_String) return Integer
   is
   begin
      Output := To_Unbounded_String ("");

      declare
         use GNAT.OS_Lib;
         Spawn_Result : Integer;
      begin
         Spawn_Result := GNAT.OS_Lib.Spawn
           (Program_Name => "/bin/sh",
            Args         => (1 => new String'("-c"),
                            2 => new String'(Command)));
         return Spawn_Result;
      exception
         when others =>
            return -1;
      end;
   end Execute_Command;

   function Command_Exists (Cmd : String) return Boolean is
      Output : Unbounded_String;
      Status : Integer;
   begin
      Status := Execute_Command ("command -v " & Cmd & " >/dev/null 2>&1", Output);
      return Status = 0;
   end Command_Exists;

   function File_Exists (Path : String) return Boolean is
   begin
      return Ada.Directories.Exists (Path);
   exception
      when others =>
         return False;
   end File_Exists;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Query Operations
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Get_Name (Self : Nix_Backend) return String is
   begin
      if Self.Is_NixOS_System then
         return "NixOS";
      else
         return "Nix";
      end if;
   end Get_Name;

   overriding function Get_PM_Type (Self : Nix_Backend) return Package_Manager_Type is
   begin
      return Nix;
   end Get_PM_Type;

   overriding function Is_Available (Self : Nix_Backend) return Boolean is
   begin
      if not Self.Checked then
         return Command_Exists ("nix-env");
      end if;
      return Self.Available;
   end Is_Available;

   overriding function Supports_Transactions (Self : Nix_Backend) return Boolean is
   begin
      --  Nix always uses atomic transactions (generations)
      return True;
   end Supports_Transactions;

   overriding function Supports_Rollback (Self : Nix_Backend) return Boolean is
   begin
      --  Nix has native rollback via generation switching
      return True;
   end Supports_Rollback;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Package Queries
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Search
     (Self  : Nix_Backend;
      Query : String;
      Limit : Positive := 100) return Package_List_Access
   is
      Result : Package_List_Access := new Package_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix search nixpkgs <query>
      Status := Execute_Command
        ("nix search nixpkgs " & Query & " 2>/dev/null | head -" & Positive'Image (Limit * 3),
         Output);
      return Result;
   end Search;

   overriding function Get_Installed
     (Self : Nix_Backend) return Package_List_Access
   is
      Result : Package_List_Access := new Package_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env -q (--query)
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) & " -q 2>/dev/null",
         Output);
      return Result;
   end Get_Installed;

   overriding function Get_Upgradable
     (Self : Nix_Backend) return Package_List_Access
   is
      Result : Package_List_Access := new Package_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env -u --dry-run shows what would be upgraded
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) & " -u --dry-run 2>&1",
         Output);
      return Result;
   end Get_Upgradable;

   overriding function Get_Package_Info
     (Self : Nix_Backend;
      Name : String) return Package_Info
   is
      Info   : Package_Info;
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env -qa --description <package>
      Status := Execute_Command
        ("nix-env -qa --description " & Name & " 2>/dev/null",
         Output);
      Info.Name := Package_Name (To_Unbounded_String (Name));
      return Info;
   end Get_Package_Info;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Modification Operations
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Install
     (Self        : in Out Nix_Backend;
      Packages    : Package_List;
      Snapshot_ID : Natural := 0) return Operation_Result
   is
      Result : Operation_Result;
      Output : Unbounded_String;
      Status : Integer;
      Pkg_Names : Unbounded_String := To_Unbounded_String ("");
   begin
      --  Build package list
      for I in Packages'Range loop
         Append (Pkg_Names, " " & String (To_String (Unbounded_String (Packages (I).Name))));
      end loop;

      --  nix-env -iA nixpkgs.<package>
      --  For simplified skeleton, just use package names
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) & " -i" & To_String (Pkg_Names),
         Output);

      if Status = 0 then
         Result.Status := Success;
         Result.Changed_Count := Packages'Length;
         Result.Message := To_Unbounded_String ("Packages installed successfully");
      else
         Result.Status := Failed;
         Result.Message := To_Unbounded_String ("Installation failed");
      end if;

      return Result;
   end Install;

   overriding function Remove
     (Self        : in Out Nix_Backend;
      Packages    : Package_List;
      Purge       : Boolean := False;
      Snapshot_ID : Natural := 0) return Operation_Result
   is
      Result : Operation_Result;
      Output : Unbounded_String;
      Status : Integer;
      Pkg_Names : Unbounded_String := To_Unbounded_String ("");
   begin
      for I in Packages'Range loop
         Append (Pkg_Names, " " & String (To_String (Unbounded_String (Packages (I).Name))));
      end loop;

      --  nix-env -e <packages>
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) & " -e" & To_String (Pkg_Names),
         Output);

      if Status = 0 then
         Result.Status := Success;
         Result.Changed_Count := Packages'Length;
         Result.Message := To_Unbounded_String ("Packages removed successfully");
      else
         Result.Status := Failed;
         Result.Message := To_Unbounded_String ("Removal failed");
      end if;

      return Result;
   end Remove;

   overriding function Upgrade
     (Self        : in Out Nix_Backend;
      Packages    : Package_List;
      Snapshot_ID : Natural := 0) return Operation_Result
   is
      Result : Operation_Result;
      Output : Unbounded_String;
      Status : Integer;
   begin
      if Packages'Length = 0 then
         --  Upgrade all packages
         Status := Execute_Command
           ("nix-env -p " & To_String (Self.Profile) & " -u",
            Output);
      else
         --  Upgrade specific packages
         declare
            Pkg_Names : Unbounded_String := To_Unbounded_String ("");
         begin
            for I in Packages'Range loop
               Append (Pkg_Names, " " & String (To_String (Unbounded_String (Packages (I).Name))));
            end loop;
            Status := Execute_Command
              ("nix-env -p " & To_String (Self.Profile) & " -u" & To_String (Pkg_Names),
               Output);
         end;
      end if;

      if Status = 0 then
         Result.Status := Success;
         Result.Message := To_Unbounded_String ("Upgrade completed successfully");
      else
         Result.Status := Failed;
         Result.Message := To_Unbounded_String ("Upgrade failed");
      end if;

      return Result;
   end Upgrade;

   overriding function Upgrade_System
     (Self        : in Out Nix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result
   is
      Result : Operation_Result;
      Output : Unbounded_String;
      Status : Integer;
   begin
      if Self.Is_NixOS_System then
         --  For NixOS, use nixos-rebuild
         Status := Execute_Command ("sudo nixos-rebuild switch", Output);
      else
         --  For standalone Nix, upgrade channel and packages
         Status := Execute_Command ("nix-channel --update && nix-env -u", Output);
      end if;

      if Status = 0 then
         Result.Status := Success;
         Result.Message := To_Unbounded_String ("System upgrade completed");
      else
         Result.Status := Failed;
         Result.Message := To_Unbounded_String ("System upgrade failed");
      end if;

      return Result;
   end Upgrade_System;

   overriding function Autoremove
     (Self        : in Out Nix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result
   is
      Result : Operation_Result;
      Delete : Natural;
   begin
      Garbage_Collect (Self, Delete);
      Result.Status := Success;
      Result.Changed_Count := Delete;
      Result.Message := To_Unbounded_String ("Garbage collection completed");
      return Result;
   end Autoremove;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Cache Operations
   --  ═══════════════════════════════════════════════════════════════════════

   overriding procedure Refresh_Cache (Self : in Out Nix_Backend) is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-channel --update
      Status := Execute_Command ("nix-channel --update", Output);
   end Refresh_Cache;

   overriding procedure Clean_Cache (Self : in Out Nix_Backend) is
      Delete : Natural;
   begin
      Garbage_Collect (Self, Delete);
   end Clean_Cache;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Simulation
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Simulate_Install
     (Self     : Nix_Backend;
      Packages : Package_List) return Transaction_List
   is
      Result : Transaction_List (1 .. 0);
   begin
      --  nix-env -i --dry-run
      return Result;
   end Simulate_Install;

   overriding function Simulate_Remove
     (Self     : Nix_Backend;
      Packages : Package_List) return Transaction_List
   is
      Result : Transaction_List (1 .. 0);
   begin
      --  nix-env -e --dry-run
      return Result;
   end Simulate_Remove;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Generation Management
   --  ═══════════════════════════════════════════════════════════════════════

   function Current_Generation (Self : Nix_Backend) return Generation_ID is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env --list-generations | grep current
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) & " --list-generations 2>/dev/null | grep current",
         Output);
      --  Walking skeleton: return 1 as placeholder
      return 1;
   end Current_Generation;

   function List_Generations
     (Self  : Nix_Backend;
      Limit : Positive := 50) return Generation_List_Access
   is
      Result : Generation_List_Access := new Generation_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env --list-generations
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) & " --list-generations",
         Output);
      return Result;
   end List_Generations;

   function Get_Generation_Info
     (Self : Nix_Backend;
      ID   : Generation_ID) return Generation_Info
   is
      Info : Generation_Info;
   begin
      Info.ID := ID;
      return Info;
   end Get_Generation_Info;

   procedure Switch_Generation
     (Self    : in Out Nix_Backend;
      ID      : Generation_ID;
      Success : out Boolean)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env --switch-generation <N>
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) &
         " --switch-generation " & Generation_ID'Image (ID),
         Output);
      Success := Status = 0;
   end Switch_Generation;

   procedure Rollback
     (Self    : in Out Nix_Backend;
      Steps   : Positive := 1;
      Success : out Boolean)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env --rollback
      for I in 1 .. Steps loop
         Status := Execute_Command
           ("nix-env -p " & To_String (Self.Profile) & " --rollback",
            Output);
         exit when Status /= 0;
      end loop;
      Success := Status = 0;
   end Rollback;

   procedure Delete_Generations
     (Self    : in Out Nix_Backend;
      Keep    : Positive := 5;
      Deleted : out Natural)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-env --delete-generations +<N> (keeps N most recent)
      Status := Execute_Command
        ("nix-env -p " & To_String (Self.Profile) &
         " --delete-generations +" & Positive'Image (Keep),
         Output);
      Deleted := 0;  --  Would parse output
   end Delete_Generations;

   procedure Garbage_Collect
     (Self   : in Out Nix_Backend;
      Delete : out Natural)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  nix-collect-garbage -d (delete old generations and gc)
      Status := Execute_Command ("nix-collect-garbage -d", Output);
      Delete := 0;  --  Would parse output
   end Garbage_Collect;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Profile Support
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Set_Profile
     (Self    : in Out Nix_Backend;
      Profile : String)
   is
   begin
      Self.Profile := To_Unbounded_String (Profile);
   end Set_Profile;

   function Get_Profile (Self : Nix_Backend) return String is
   begin
      return To_String (Self.Profile);
   end Get_Profile;

   function Is_NixOS (Self : Nix_Backend) return Boolean is
   begin
      return Self.Is_NixOS_System;
   end Is_NixOS;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Factory
   --  ═══════════════════════════════════════════════════════════════════════

   function Create return Nix_Backend is
      Backend : Nix_Backend;
   begin
      Backend.Available := Command_Exists ("nix-env");
      Backend.Checked := True;
      --  Check for NixOS by looking for /etc/nixos
      Backend.Is_NixOS_System := File_Exists ("/etc/nixos/configuration.nix");
      return Backend;
   end Create;

end Backend_Nix;
