--  SPDX-License-Identifier: PMPL-1.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Backend Interface - Abstract interface for all package managers
--  DNFinition supports 50+ package managers through this unified interface

--  HONEST SPARK BOUNDARY (standards#127).
--  This unit was `pragma SPARK_Mode (On)` but is **not legal SPARK** and
--  never compiled at all:
--    * `Transaction_Item.Package` used an Ada *reserved word* as a field
--      name (no compiler accepts it) — fixed (renamed `Pkg`);
--    * the modification operations Install/Remove/Upgrade/
--      Upgrade_System/Autoremove are *functions* with an `in out`
--      controlling parameter, which SPARK forbids (SPARK RM 4.5.2).
--  `SPARK_Mode (On)` over non-SPARK code is theatre; gnatprove could
--  never analyse it. The correct fix (state-mutating `function`s ->
--  `procedure`s with `out Result`, across the interface and every
--  backend body) is a breaking redesign, OWED and tracked under
--  standards#127 — it must not be faked. Until then this unit is
--  honestly marked OUT of the SPARK boundary. The Ada 2022
--  `Pre'Class`/`Post'Class` aspects below remain as runtime-checked
--  (`-gnata`) behavioural contracts and as the spec for that future
--  SPARK refactor.
pragma SPARK_Mode (Off);

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
      Pkg     : Package_Info;
      --  Renamed from `Package`: that is an Ada reserved word and was a
      --  hard legality error (backend_interface.ads:71) that prevented the
      --  dnfinition subsystem from compiling at all — the concrete reason
      --  the old SPARK "formally verified" banners were pure theatre
      --  (GNATprove can prove nothing about code that does not compile).
      --  Field is unreferenced anywhere; rename is purely local.
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
     is abstract
     with Post'Class => Get_Name'Result'Length > 0;
   --  Behavioural contract (Liskov): every backend has a non-empty name.

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
     is abstract
     with Pre'Class => Query'Length > 0;
   --  Behavioural contract: a search query must be non-empty.

   function Get_Installed
     (Self : Package_Manager_Backend) return Package_List_Access
     is abstract;

   function Get_Upgradable
     (Self : Package_Manager_Backend) return Package_List_Access
     is abstract;

   function Get_Package_Info
     (Self : Package_Manager_Backend;
      Name : String) return Package_Info
     is abstract
     with Pre'Class => Name'Length > 0;
   --  Behavioural contract: a package name must be non-empty.

   --  Modification operations (all should support snapshot/rollback).
   --
   --  HONEST SPARK BOUNDARY (standards#127): these five operations are
   --  declared as *functions* with an `in out` controlling parameter and
   --  a returned `Operation_Result`. A function with an `in out`
   --  parameter is **not legal SPARK** (SPARK RM 4.5.2). The whole unit
   --  carried `pragma SPARK_Mode (On)` while being non-SPARK — i.e.
   --  SPARK *theatre*: `gnatprove` could never analyse it (and the
   --  reserved-word `Package` field above means it never compiled at
   --  all). Rather than hide that, the genuinely-effectful modification
   --  operations are explicitly placed OUTSIDE the SPARK boundary with
   --  `SPARK_Mode => Off`. This makes the boundary truthful and lets
   --  gnatprove genuinely verify the rest of the spec + plugin_registry.
   --
   --  The proper fix (OWED, tracked standards#127) is a breaking
   --  redesign: state-mutating `function`s -> `procedure`s with an
   --  `out Result : Operation_Result` parameter, across the interface
   --  and every backend (backend_guix, backend_nix, …). That refactor
   --  is out of scope for this PR; it must not be faked. The intended
   --  soundness contract — *a `Success` result must not report
   --  Failed_Count > 0* — is recorded here for that future work.
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
      Backend : Backend_Access)
     with Pre => Backend /= null;
   --  Register a backend implementation (a null backend is rejected).

   function Get_Backend (PM_Type : Package_Manager_Type) return Backend_Access;
   --  Get backend for a package manager type

   function Get_Primary_Backend return Backend_Access;
   --  Get backend for the primary package manager on current system

   function List_Available_Backends return Package_Manager_Type;
   --  TODO: Should return array, simplified for now

end Backend_Interface;
