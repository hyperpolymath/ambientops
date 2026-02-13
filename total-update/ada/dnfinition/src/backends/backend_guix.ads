--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Backend_Guix - GNU Guix package manager backend
--  Guix uses generations (profiles) for atomic transactions and rollback

pragma SPARK_Mode (On);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Backend_Interface;     use Backend_Interface;
with Platform_Detection;    use Platform_Detection;

package Backend_Guix is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Guix Generation Support (Native Transactions)
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
   --  Guix Backend Implementation
   --  ═══════════════════════════════════════════════════════════════════════

   type Guix_Backend is new Package_Manager_Backend with private;

   --  Query operations
   overriding function Get_Name (Self : Guix_Backend) return String;
   overriding function Get_PM_Type (Self : Guix_Backend) return Package_Manager_Type;
   overriding function Is_Available (Self : Guix_Backend) return Boolean;
   overriding function Supports_Transactions (Self : Guix_Backend) return Boolean;
   overriding function Supports_Rollback (Self : Guix_Backend) return Boolean;

   --  Package queries
   overriding function Search
     (Self  : Guix_Backend;
      Query : String;
      Limit : Positive := 100) return Package_List_Access;

   overriding function Get_Installed
     (Self : Guix_Backend) return Package_List_Access;

   overriding function Get_Upgradable
     (Self : Guix_Backend) return Package_List_Access;

   overriding function Get_Package_Info
     (Self : Guix_Backend;
      Name : String) return Package_Info;

   --  Modification operations (all create new generations)
   overriding function Install
     (Self        : in out Guix_Backend;
      Packages    : Package_List;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Remove
     (Self        : in Out Guix_Backend;
      Packages    : Package_List;
      Purge       : Boolean := False;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Upgrade
     (Self        : in Out Guix_Backend;
      Packages    : Package_List;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Upgrade_System
     (Self        : in Out Guix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result;

   overriding function Autoremove
     (Self        : in Out Guix_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result;

   --  Cache operations
   overriding procedure Refresh_Cache (Self : in Out Guix_Backend);
   overriding procedure Clean_Cache (Self : in Out Guix_Backend);

   --  Simulation
   overriding function Simulate_Install
     (Self     : Guix_Backend;
      Packages : Package_List) return Transaction_List;

   overriding function Simulate_Remove
     (Self     : Guix_Backend;
      Packages : Package_List) return Transaction_List;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Guix-Specific Operations (Generation Management)
   --  ═══════════════════════════════════════════════════════════════════════

   function Current_Generation (Self : Guix_Backend) return Generation_ID;
   --  Get the current generation number

   function List_Generations
     (Self  : Guix_Backend;
      Limit : Positive := 50) return Generation_List_Access;
   --  List all available generations

   function Get_Generation_Info
     (Self : Guix_Backend;
      ID   : Generation_ID) return Generation_Info
     with Pre => Valid_Generation (ID);
   --  Get info about a specific generation

   procedure Switch_Generation
     (Self    : in Out Guix_Backend;
      ID      : Generation_ID;
      Success : out Boolean)
     with Pre => Valid_Generation (ID);
   --  Switch to a specific generation

   procedure Rollback
     (Self    : in Out Guix_Backend;
      Steps   : Positive := 1;
      Success : out Boolean);
   --  Rollback N generations

   procedure Delete_Generation
     (Self    : in Out Guix_Backend;
      ID      : Generation_ID;
      Success : out Boolean)
     with Pre => Valid_Generation (ID);
   --  Delete a specific generation

   procedure Garbage_Collect
     (Self   : in Out Guix_Backend;
      Delete : out Natural);
   --  Run guix gc to clean up store

   --  ═══════════════════════════════════════════════════════════════════════
   --  Profile Support
   --  ═══════════════════════════════════════════════════════════════════════

   Default_Profile : constant String := "~/.guix-profile";
   System_Profile  : constant String := "/run/current-system/profile";

   procedure Set_Profile
     (Self    : in Out Guix_Backend;
      Profile : String);
   --  Set the target profile (user or system)

   function Get_Profile (Self : Guix_Backend) return String;
   --  Get the current profile path

   function Is_System_Profile (Self : Guix_Backend) return Boolean;
   --  True if operating on system profile (requires root)

   --  ═══════════════════════════════════════════════════════════════════════
   --  Factory Function
   --  ═══════════════════════════════════════════════════════════════════════

   function Create return Guix_Backend;
   --  Create a new Guix backend instance

private

   type Guix_Backend is new Package_Manager_Backend with record
      Profile    : Unbounded_String := To_Unbounded_String (Default_Profile);
      Available  : Boolean := False;
      Checked    : Boolean := False;
   end record;

end Backend_Guix;
