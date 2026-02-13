--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Plugin_Registry - Dynamic plugin architecture for package manager backends
--
--  This module provides:
--  1. Dynamic registration and discovery of package manager backends
--  2. Plugin metadata and capability declaration
--  3. Priority-based backend selection
--  4. Hot-reload support for plugins (future)
--
--  Plugins can be:
--  - Built-in (compiled with DNFinition)
--  - External (loaded from shared libraries or scripts)
--  - User-defined (configuration-based wrappers)

pragma SPARK_Mode (On);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with Backend_Interface;     use Backend_Interface;
with Platform_Detection;    use Platform_Detection;

package Plugin_Registry is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Plugin Capability Flags
   --  ═══════════════════════════════════════════════════════════════════════

   type Plugin_Capability is
     (Cap_Install,           --  Can install packages
      Cap_Remove,            --  Can remove packages
      Cap_Upgrade,           --  Can upgrade packages
      Cap_Search,            --  Can search packages
      Cap_Query,             --  Can query installed packages
      Cap_Transactions,      --  Has atomic transactions
      Cap_Native_Rollback,   --  Has built-in rollback (generations)
      Cap_Dry_Run,           --  Supports simulation
      Cap_Pinning,           --  Supports version pinning
      Cap_Hold,              --  Can hold packages
      Cap_Autoremove,        --  Can remove orphans
      Cap_Cache_Clean,       --  Can clean package cache
      Cap_Parallel_Download, --  Supports parallel downloads
      Cap_Verify,            --  Can verify package integrity
      Cap_Dependencies,      --  Reports dependency information
      Cap_Provides,          --  Reports what packages provide
      Cap_Files,             --  Can list files in packages
      Cap_History,           --  Tracks operation history
      Cap_Offline);          --  Can work offline

   type Capability_Set is array (Plugin_Capability) of Boolean;

   --  Convenience capability sets
   Full_Capabilities : constant Capability_Set := (others => True);
   Read_Only_Capabilities : constant Capability_Set :=
     (Cap_Search | Cap_Query | Cap_Dependencies | Cap_Provides | Cap_Files => True,
      others => False);

   --  ═══════════════════════════════════════════════════════════════════════
   --  Plugin Metadata
   --  ═══════════════════════════════════════════════════════════════════════

   type Plugin_Type is
     (Plugin_Builtin,        --  Compiled with DNFinition
      Plugin_External,       --  Loaded dynamically
      Plugin_Script,         --  Shell script wrapper
      Plugin_Config);        --  Configuration-defined

   type Plugin_Status is
     (Status_Available,      --  Ready to use
      Status_Unavailable,    --  Tool not installed
      Status_Disabled,       --  Disabled by user
      Status_Error,          --  Failed to load
      Status_Degraded);      --  Working with reduced capability

   type Plugin_Priority is range 0 .. 100;
   --  Higher = preferred when multiple backends can handle a task
   Default_Priority : constant Plugin_Priority := 50;

   type Plugin_Metadata is record
      --  Identification
      ID          : Unbounded_String;  --  Unique identifier (e.g., "guix", "apt")
      Name        : Unbounded_String;  --  Display name
      Version     : Unbounded_String;  --  Plugin version
      Description : Unbounded_String;

      --  Classification
      PM_Type     : Package_Manager_Type := None;
      Plugin_Kind : Plugin_Type := Plugin_Builtin;
      Status      : Plugin_Status := Status_Unavailable;
      Priority    : Plugin_Priority := Default_Priority;

      --  Capabilities
      Capabilities : Capability_Set := (others => False);

      --  Requirements
      Required_Commands : Unbounded_String;  --  Space-separated command names
      Config_Path       : Unbounded_String;  --  Optional config file

      --  Recovery support
      Has_Native_Recovery : Boolean := False;  --  Like Guix/Nix generations
      Preferred_Snapshot  : Snapshot_Backend := None;
   end record;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Plugin Interface
   --  ═══════════════════════════════════════════════════════════════════════

   type Plugin is interface;
   type Plugin_Access is access all Plugin'Class;

   function Get_Metadata (Self : Plugin) return Plugin_Metadata is abstract;
   --  Return plugin metadata

   function Get_Backend (Self : Plugin) return Backend_Access is abstract;
   --  Get the actual backend implementation

   function Check_Available (Self : Plugin) return Boolean is abstract;
   --  Check if this plugin can be used on the current system

   procedure Initialize (Self : in Out Plugin) is abstract;
   --  Initialize the plugin (called after registration)

   procedure Shutdown (Self : in Out Plugin) is abstract;
   --  Clean up plugin resources

   --  ═══════════════════════════════════════════════════════════════════════
   --  Plugin Registry
   --  ═══════════════════════════════════════════════════════════════════════

   Max_Plugins : constant := 100;

   type Plugin_Entry is record
      Meta   : Plugin_Metadata;
      Impl   : Plugin_Access := null;
      Active : Boolean := False;
   end record;

   --  Registration and discovery
   procedure Register_Plugin (P : Plugin_Access)
     with Pre => P /= null;
   --  Register a new plugin

   procedure Unregister_Plugin (ID : String);
   --  Remove a plugin from the registry

   procedure Discover_Plugins;
   --  Scan for available plugins and update status

   procedure Refresh_Plugin_Status;
   --  Re-check availability of all plugins

   --  Query operations
   function Get_Plugin (ID : String) return Plugin_Access;
   --  Get a specific plugin by ID

   function Get_Plugin_By_Type (PM : Package_Manager_Type) return Plugin_Access;
   --  Get plugin for a specific package manager type

   function Get_Available_Plugins return Natural;
   --  Count of available plugins

   function Get_Plugin_Metadata (ID : String) return Plugin_Metadata;
   --  Get metadata for a plugin

   --  Priority-based selection
   function Get_Best_Plugin_For
     (Required : Capability_Set) return Plugin_Access;
   --  Get highest-priority plugin that has all required capabilities

   function Get_Plugins_With_Capability
     (Cap : Plugin_Capability) return Natural;
   --  Count plugins with a specific capability

   --  Status management
   procedure Enable_Plugin (ID : String);
   procedure Disable_Plugin (ID : String);
   function Is_Plugin_Enabled (ID : String) return Boolean;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Built-in Plugin Factories
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Register_Builtin_Plugins;
   --  Register all built-in plugins (Guix, Nix, etc.)

   function Create_Guix_Plugin return Plugin_Access;
   function Create_Nix_Plugin return Plugin_Access;
   function Create_Apt_Plugin return Plugin_Access;
   function Create_DNF_Plugin return Plugin_Access;
   function Create_Pacman_Plugin return Plugin_Access;
   function Create_Flatpak_Plugin return Plugin_Access;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Plugin Discovery Paths
   --  ═══════════════════════════════════════════════════════════════════════

   User_Plugin_Dir    : constant String := "~/.config/dnfinition/plugins";
   System_Plugin_Dir  : constant String := "/usr/share/dnfinition/plugins";
   Local_Plugin_Dir   : constant String := "/usr/local/share/dnfinition/plugins";

end Plugin_Registry;
