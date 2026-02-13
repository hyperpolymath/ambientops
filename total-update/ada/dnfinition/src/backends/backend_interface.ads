--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Backend Interface - Abstract interface for all package managers
--  DNFinition supports 50+ package managers through this unified interface

pragma SPARK_Mode (On);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Platform_Detection;    use Platform_Detection;

package Backend_Interface is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Package Information Types
   --  ═══════════════════════════════════════════════════════════════════════

   type Package_Name is new Unbounded_String;
   type Package_Version is new Unbounded_String;

   type Package_State is
     (Not_Installed,
      Installed,
      Upgradable,
      Downgraded,
      Orphaned,       --  No longer in repositories
      Pinned,         --  Held at specific version
      Broken);        --  Dependency issues

   type Package_Source is
     (Repository,     --  From official repos
      Third_Party,    --  From additional repos
      Local,          --  From local file
      Container,      --  Flatpak/Snap/AppImage
      Language);      --  pip/cargo/etc

   type Package_Info is record
      Name           : Package_Name;
      Version        : Package_Version;
      Available_Ver  : Package_Version;  --  For upgradable packages
      State          : Package_State := Not_Installed;
      Source         : Package_Source := Repository;
      Description    : Unbounded_String;
      Size_Installed : Natural := 0;     --  KB
      Size_Download  : Natural := 0;     --  KB
      Is_Essential   : Boolean := False;
      Is_Automatic   : Boolean := False; --  Installed as dependency
   end record;

   type Package_List is array (Positive range <>) of Package_Info;
   type Package_List_Access is access all Package_List;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Transaction Types
   --  ═══════════════════════════════════════════════════════════════════════

   type Transaction_Kind is
     (Install,
      Remove,
      Upgrade,
      Downgrade,
      Reinstall,
      Auto_Remove,    --  Remove unused dependencies
      Mark_Manual,    --  Mark as manually installed
      Mark_Auto,      --  Mark as automatic dependency
      Pin,
      Unpin);

   type Transaction_Item is record
      Kind    : Transaction_Kind;
      Package : Package_Info;
   end record;

   type Transaction_List is array (Positive range <>) of Transaction_Item;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Operation Result Types
   --  ═══════════════════════════════════════════════════════════════════════

   type Operation_Status is
     (Success,
      Partial_Success,  --  Some packages failed
      Failed,
      Cancelled,
      Rolled_Back);

   type Operation_Result is record
      Status        : Operation_Status := Success;
      Message       : Unbounded_String;
      Snapshot_ID   : Natural := 0;  --  For rollback
      Changed_Count : Natural := 0;
      Failed_Count  : Natural := 0;
   end record;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Abstract Package Manager Interface
   --  ═══════════════════════════════════════════════════════════════════════

   type Package_Manager_Backend is interface;
   type Backend_Access is access all Package_Manager_Backend'Class;

   --  Query operations
   function Get_Name (Self : Package_Manager_Backend) return String
     is abstract;

   function Get_PM_Type (Self : Package_Manager_Backend)
     return Package_Manager_Type
     is abstract;

   function Is_Available (Self : Package_Manager_Backend) return Boolean
     is abstract;

   function Supports_Transactions (Self : Package_Manager_Backend)
     return Boolean
     is abstract;

   function Supports_Rollback (Self : Package_Manager_Backend)
     return Boolean
     is abstract;

   --  Package queries
   function Search
     (Self    : Package_Manager_Backend;
      Query   : String;
      Limit   : Positive := 100) return Package_List_Access
     is abstract;

   function Get_Installed
     (Self : Package_Manager_Backend) return Package_List_Access
     is abstract;

   function Get_Upgradable
     (Self : Package_Manager_Backend) return Package_List_Access
     is abstract;

   function Get_Package_Info
     (Self : Package_Manager_Backend;
      Name : String) return Package_Info
     is abstract;

   --  Modification operations (all should support snapshot/rollback)
   function Install
     (Self         : in out Package_Manager_Backend;
      Packages     : Package_List;
      Snapshot_ID  : Natural := 0) return Operation_Result
     is abstract;

   function Remove
     (Self         : in out Package_Manager_Backend;
      Packages     : Package_List;
      Purge        : Boolean := False;
      Snapshot_ID  : Natural := 0) return Operation_Result
     is abstract;

   function Upgrade
     (Self         : in Out Package_Manager_Backend;
      Packages     : Package_List;  --  Empty = upgrade all
      Snapshot_ID  : Natural := 0) return Operation_Result
     is abstract;

   function Upgrade_System
     (Self        : in out Package_Manager_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result
     is abstract;

   function Autoremove
     (Self        : in Out Package_Manager_Backend;
      Snapshot_ID : Natural := 0) return Operation_Result
     is abstract;

   --  Cache operations
   procedure Refresh_Cache (Self : in Out Package_Manager_Backend)
     is abstract;

   procedure Clean_Cache (Self : in Out Package_Manager_Backend)
     is abstract;

   --  Dry-run support
   function Simulate_Install
     (Self     : Package_Manager_Backend;
      Packages : Package_List) return Transaction_List
     is abstract;

   function Simulate_Remove
     (Self     : Package_Manager_Backend;
      Packages : Package_List) return Transaction_List
     is abstract;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Backend Registry
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Register_Backend
     (PM_Type : Package_Manager_Type;
      Backend : Backend_Access);
   --  Register a backend implementation

   function Get_Backend (PM_Type : Package_Manager_Type) return Backend_Access;
   --  Get backend for a package manager type

   function Get_Primary_Backend return Backend_Access;
   --  Get backend for the primary package manager on current system

   function List_Available_Backends return Package_Manager_Type;
   --  TODO: Should return array, simplified for now

end Backend_Interface;
