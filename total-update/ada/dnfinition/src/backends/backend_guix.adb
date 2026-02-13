--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Backend_Guix - GNU Guix package manager backend implementation

pragma SPARK_Mode (Off);  --  Implementation uses shell commands

with Ada.Text_IO;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with GNAT.Expect;

package body Backend_Guix is

   use Ada.Text_IO;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Helper Functions
   --  ═══════════════════════════════════════════════════════════════════════

   function Execute_Command
     (Command : String;
      Output  : out Unbounded_String) return Integer
   is
      Args    : GNAT.OS_Lib.Argument_List_Access;
      Success : Boolean;
      Status  : Integer;
   begin
      --  For walking skeleton, simplified execution
      --  Full implementation would use GNAT.Expect for streaming output
      Output := To_Unbounded_String ("");

      declare
         use GNAT.OS_Lib;
         Spawn_Result : Integer;
      begin
         --  Execute command and capture exit code
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

   --  ═══════════════════════════════════════════════════════════════════════
   --  Query Operations
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Get_Name (Self : Guix_Backend) return String is
   begin
      return "GNU Guix";
   end Get_Name;

   overriding function Get_PM_Type (Self : Guix_Backend) return Package_Manager_Type is
   begin
      return Guix;
   end Get_PM_Type;

   overriding function Is_Available (Self : Guix_Backend) return Boolean is
   begin
      if not Self.Checked then
         --  Check for guix binary
         return Command_Exists ("guix");
      end if;
      return Self.Available;
   end Is_Available;

   overriding function Supports_Transactions (Self : Guix_Backend) return Boolean is
   begin
      --  Guix always uses atomic transactions (generations)
      return True;
   end Supports_Transactions;

   overriding function Supports_Rollback (Self : Guix_Backend) return Boolean is
   begin
      --  Guix has native rollback via generation switching
      return True;
   end Supports_Rollback;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Package Queries
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Search
     (Self  : Guix_Backend;
      Query : String;
      Limit : Positive := 100) return Package_List_Access
   is
      Result : Package_List_Access := new Package_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix search <query>
      Status := Execute_Command
        ("guix search " & Query & " 2>/dev/null | head -" & Positive'Image (Limit * 10),
         Output);
      --  Parse output (walking skeleton: return empty for now)
      return Result;
   end Search;

   overriding function Get_Installed
     (Self : Guix_Backend) return Package_List_Access
   is
      Result : Package_List_Access := new Package_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix package -I (--list-installed)
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) & " -I 2>/dev/null",
         Output);
      --  Parse output (walking skeleton: return empty for now)
      return Result;
   end Get_Installed;

   overriding function Get_Upgradable
     (Self : Guix_Backend) return Package_List_Access
   is
      Result : Package_List_Access := new Package_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix package -u --dry-run shows what would be upgraded
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) & " -u --dry-run 2>/dev/null",
         Output);
      return Result;
   end Get_Upgradable;

   overriding function Get_Package_Info
     (Self : Guix_Backend;
      Name : String) return Package_Info
   is
      Info   : Package_Info;
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix show <package>
      Status := Execute_Command ("guix show " & Name & " 2>/dev/null", Output);
      Info.Name := Package_Name (To_Unbounded_String (Name));
      return Info;
   end Get_Package_Info;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Modification Operations
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Install
     (Self        : in Out Guix_Backend;
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

      --  guix package -i <packages>
      --  This automatically creates a new generation
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) & " -i" & To_String (Pkg_Names),
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
     (Self        : in Out Guix_Backend;
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

      --  guix package -r <packages>
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) & " -r" & To_String (Pkg_Names),
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
     (Self        : in Out Guix_Backend;
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
           ("guix package -p " & To_String (Self.Profile) & " -u",
            Output);
      else
         --  Upgrade specific packages (reinstall latest)
         declare
            Pkg_Names : Unbounded_String := To_Unbounded_String ("");
         begin
            for I in Packages'Range loop
               Append (Pkg_Names, " " & String (To_String (Unbounded_String (Packages (I).Name))));
            end loop;
            Status := Execute_Command
              ("guix package -p " & To_String (Self.Profile) & " -u" & To_String (Pkg_Names),
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
     (Self        : in Out Guix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result
   is
      Result : Operation_Result;
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  For Guix System, use guix system reconfigure
      if Self.Is_System_Profile then
         Status := Execute_Command ("guix system reconfigure /etc/config.scm", Output);
      else
         --  For user profile, just upgrade all
         Status := Execute_Command
           ("guix package -p " & To_String (Self.Profile) & " -u",
            Output);
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
     (Self        : in Out Guix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result
   is
      Result : Operation_Result;
      Delete : Natural;
   begin
      --  Guix uses garbage collection, not autoremove
      Garbage_Collect (Self, Delete);
      Result.Status := Success;
      Result.Changed_Count := Delete;
      Result.Message := To_Unbounded_String ("Garbage collection completed");
      return Result;
   end Autoremove;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Cache Operations
   --  ═══════════════════════════════════════════════════════════════════════

   overriding procedure Refresh_Cache (Self : in Out Guix_Backend) is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix pull updates the package definitions
      Status := Execute_Command ("guix pull", Output);
   end Refresh_Cache;

   overriding procedure Clean_Cache (Self : in Out Guix_Backend) is
      Delete : Natural;
   begin
      Garbage_Collect (Self, Delete);
   end Clean_Cache;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Simulation
   --  ═══════════════════════════════════════════════════════════════════════

   overriding function Simulate_Install
     (Self     : Guix_Backend;
      Packages : Package_List) return Transaction_List
   is
      Result : Transaction_List (1 .. 0);
   begin
      --  guix package -i --dry-run
      return Result;
   end Simulate_Install;

   overriding function Simulate_Remove
     (Self     : Guix_Backend;
      Packages : Package_List) return Transaction_List
   is
      Result : Transaction_List (1 .. 0);
   begin
      --  guix package -r --dry-run
      return Result;
   end Simulate_Remove;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Generation Management
   --  ═══════════════════════════════════════════════════════════════════════

   function Current_Generation (Self : Guix_Backend) return Generation_ID is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  Parse current generation from guix package -l
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) & " -l 2>/dev/null | head -1",
         Output);
      --  Walking skeleton: return 1 as placeholder
      return 1;
   end Current_Generation;

   function List_Generations
     (Self  : Guix_Backend;
      Limit : Positive := 50) return Generation_List_Access
   is
      Result : Generation_List_Access := new Generation_List (1 .. 0);
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix package -l lists all generations
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) & " -l",
         Output);
      return Result;
   end List_Generations;

   function Get_Generation_Info
     (Self : Guix_Backend;
      ID   : Generation_ID) return Generation_Info
   is
      Info : Generation_Info;
   begin
      Info.ID := ID;
      return Info;
   end Get_Generation_Info;

   procedure Switch_Generation
     (Self    : in Out Guix_Backend;
      ID      : Generation_ID;
      Success : out Boolean)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix package -S <generation>
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) &
         " -S " & Generation_ID'Image (ID),
         Output);
      Success := Status = 0;
   end Switch_Generation;

   procedure Rollback
     (Self    : in Out Guix_Backend;
      Steps   : Positive := 1;
      Success : out Boolean)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix package --roll-back (goes back one generation)
      --  For multiple steps, we'd need to call multiple times or use -S
      for I in 1 .. Steps loop
         Status := Execute_Command
           ("guix package -p " & To_String (Self.Profile) & " --roll-back",
            Output);
         exit when Status /= 0;
      end loop;
      Success := Status = 0;
   end Rollback;

   procedure Delete_Generation
     (Self    : in Out Guix_Backend;
      ID      : Generation_ID;
      Success : out Boolean)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix package -d <generation>
      Status := Execute_Command
        ("guix package -p " & To_String (Self.Profile) &
         " -d " & Generation_ID'Image (ID),
         Output);
      Success := Status = 0;
   end Delete_Generation;

   procedure Garbage_Collect
     (Self   : in Out Guix_Backend;
      Delete : out Natural)
   is
      Output : Unbounded_String;
      Status : Integer;
   begin
      --  guix gc (garbage collect)
      Status := Execute_Command ("guix gc", Output);
      Delete := 0;  --  Would parse output for actual count
   end Garbage_Collect;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Profile Support
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Set_Profile
     (Self    : in Out Guix_Backend;
      Profile : String)
   is
   begin
      Self.Profile := To_Unbounded_String (Profile);
   end Set_Profile;

   function Get_Profile (Self : Guix_Backend) return String is
   begin
      return To_String (Self.Profile);
   end Get_Profile;

   function Is_System_Profile (Self : Guix_Backend) return Boolean is
   begin
      return To_String (Self.Profile) = System_Profile;
   end Is_System_Profile;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Factory
   --  ═══════════════════════════════════════════════════════════════════════

   function Create return Guix_Backend is
      Backend : Guix_Backend;
   begin
      Backend.Available := Command_Exists ("guix");
      Backend.Checked := True;
      return Backend;
   end Create;

end Backend_Guix;
