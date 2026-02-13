--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Backend_Nix - Nix package manager backend
--  Nix uses generations for atomic transactions and rollback

pragma SPARK_Mode (On);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Backend_Interface;     use Backend_Interface;
with Platform_Detection;    use Platform_Detection;

package Backend_Nix is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Nix Generation Support (Native Transactions)
   --  ═══════════════════════════════════════════════════════════════════════

   type Generation_ID is new Natural;
   Null_Generation : constant Generation_ID := 0;

   function Valid_Generation (ID : Generation_ID) return Boolean is
     (ID > 0);

   type Generation_Info is record
      ID          : Generation_ID := Null_Generation;
      Timestamp   : Unbounded_String;
      Description : Unbounded_String;
      Is_Current  : Boolean := False;
   end record;

   type Generation_List is array (Positive range <>) of Generation_Info;
   type Generation_List_Access is access all Generation_List;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Nix Backend Implementation
   --  ═══════════════════════════════════════════════════════════════════════

   type Nix_Backend is new Package_Manager_Backend with private;

   --  Query operations
   overriding function Get_Name (Self : Nix_Backend) return String;
   overriding function Get_PM_Type (Self : Nix_Backend) return Package_Manager_Type;
   overriding function Is_Available (Self : Nix_Backend) return Boolean;
   overriding function Supports_Transactions (Self : Nix_Backend) return Boolean;
   overriding function Supports_Rollback (Self : Nix_Backend) return Boolean;

   --  Package queries
   overriding function Search
     (Self  : Nix_Backend;
      Query : String;
      Limit : Positive := 100) return Package_List_Access;

   overriding function Get_Installed
     (Self : Nix_Backend) return Package_List_Access;

   overriding function Get_Upgradable
     (Self : Nix_Backend) return Package_List_Access;

   overriding function Get_Package_Info
     (Self : Nix_Backend;
      Name : String) return Package_Info;

   --  Modification operations (all create new generations)
   overriding function Install
     (Self        : in Out Nix_Backend;
      Packages    : Package_List;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Remove
     (Self        : in Out Nix_Backend;
      Packages    : Package_List;
      Purge       : Boolean := False;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Upgrade
     (Self        : in Out Nix_Backend;
      Packages    : Package_List;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Upgrade_System
     (Self        : in Out Nix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Autoremove
     (Self        : in Out Nix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result;

   --  Cache operations
   overriding procedure Refresh_Cache (Self : in Out Nix_Backend);
   overriding procedure Clean_Cache (Self : in Out Nix_Backend);

   --  Simulation
   overriding function Simulate_Install
     (Self     : Nix_Backend;
      Packages : Package_List) return Transaction_List;

   overriding function Simulate_Remove
     (Self     : Nix_Backend;
      Packages : Package_List) return Transaction_List;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Nix-Specific Operations (Generation Management)
   --  ═══════════════════════════════════════════════════════════════════════

   function Current_Generation (Self : Nix_Backend) return Generation_ID;
   --  Get the current generation number

   function List_Generations
     (Self  : Nix_Backend;
      Limit : Positive := 50) return Generation_List_Access;
   --  List all available generations

   function Get_Generation_Info
     (Self : Nix_Backend;
      ID   : Generation_ID) return Generation_Info
     with Pre => Valid_Generation (ID);
   --  Get info about a specific generation

   procedure Switch_Generation
     (Self    : in Out Nix_Backend;
      ID      : Generation_ID;
      Success : out Boolean)
     with Pre => Valid_Generation (ID);
   --  Switch to a specific generation

   procedure Rollback
     (Self    : in Out Nix_Backend;
      Steps   : Positive := 1;
      Success : out Boolean);
   --  Rollback N generations

   procedure Delete_Generations
     (Self    : in Out Nix_Backend;
      Keep    : Positive := 5;
      Deleted : out Natural);
   --  Delete old generations, keeping N most recent

   procedure Garbage_Collect
     (Self   : in Out Nix_Backend;
      Delete : out Natural);
   --  Run nix-collect-garbage

   --  ═══════════════════════════════════════════════════════════════════════
   --  Profile Support
   --  ═══════════════════════════════════════════════════════════════════════

   Default_Profile : constant String := "~/.nix-profile";
   System_Profile  : constant String := "/nix/var/nix/profiles/system";

   procedure Set_Profile
     (Self    : in Out Nix_Backend;
      Profile : String);
   --  Set the target profile (user or system)

   function Get_Profile (Self : Nix_Backend) return String;
   --  Get the current profile path

   function Is_NixOS (Self : Nix_Backend) return Boolean;
   --  True if running on NixOS (vs standalone Nix)

   --  ═══════════════════════════════════════════════════════════════════════
   --  Factory Function
   --  ═══════════════════════════════════════════════════════════════════════

   function Create return Nix_Backend;
   --  Create a new Nix backend instance

private

   type Nix_Backend is new Package_Manager_Backend with record
      Profile    : Unbounded_String := To_Unbounded_String (Default_Profile);
      Available  : Boolean := False;
      Checked    : Boolean := False;
      Is_NixOS_System : Boolean := False;
   end record;

end Backend_Nix;
