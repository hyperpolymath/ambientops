--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Plugin_Registry - Implementation of plugin architecture

pragma SPARK_Mode (Off);  --  Implementation uses dynamic structures

with Ada.Directories;
with GNAT.OS_Lib;

package body Plugin_Registry is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Plugin Storage
   --  ═══════════════════════════════════════════════════════════════════════

   type Plugin_Array is array (1 .. Max_Plugins) of Plugin_Entry;

   Plugins : Plugin_Array;
   Plugin_Count : Natural := 0;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Helper Functions
   --  ═══════════════════════════════════════════════════════════════════════

   function Command_Exists (Cmd : String) return Boolean is
      use GNAT.OS_Lib;
   begin
      return Locate_Exec_On_Path (Cmd) /= null;
   exception
      when others => return False;
   end Command_Exists;

   function Find_Plugin_Index (ID : String) return Natural is
   begin
      for I in 1 .. Plugin_Count loop
         if To_String (Plugins (I).Meta.ID) = ID then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Plugin_Index;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Registration and Discovery
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Register_Plugin (P : Plugin_Access) is
      Meta : Plugin_Metadata;
   begin
      if Plugin_Count >= Max_Plugins then
         return;  --  Registry full
      end if;

      Meta := P.Get_Metadata;

      --  Check for duplicate
      if Find_Plugin_Index (To_String (Meta.ID)) /= 0 then
         return;  --  Already registered
      end if;

      Plugin_Count := Plugin_Count + 1;
      Plugins (Plugin_Count) :=
        (Meta   => Meta,
         Impl   => P,
         Active => True);

      --  Initialize the plugin
      P.Initialize;
   end Register_Plugin;

   procedure Unregister_Plugin (ID : String) is
      Idx : constant Natural := Find_Plugin_Index (ID);
   begin
      if Idx = 0 then
         return;
      end if;

      --  Shutdown the plugin
      if Plugins (Idx).Impl /= null then
         Plugins (Idx).Impl.Shutdown;
      end if;

      --  Shift remaining plugins down
      for I in Idx .. Plugin_Count - 1 loop
         Plugins (I) := Plugins (I + 1);
      end loop;
      Plugin_Count := Plugin_Count - 1;
   end Unregister_Plugin;

   procedure Discover_Plugins is
   begin
      --  Register built-in plugins
      Register_Builtin_Plugins;

      --  Scan plugin directories for external plugins
      --  (Future: load from User_Plugin_Dir, System_Plugin_Dir, Local_Plugin_Dir)

      --  Update status of all plugins
      Refresh_Plugin_Status;
   end Discover_Plugins;

   procedure Refresh_Plugin_Status is
   begin
      for I in 1 .. Plugin_Count loop
         if Plugins (I).Impl /= null then
            if Plugins (I).Impl.Check_Available then
               Plugins (I).Meta.Status := Status_Available;
            else
               Plugins (I).Meta.Status := Status_Unavailable;
            end if;
         end if;
      end loop;
   end Refresh_Plugin_Status;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Query Operations
   --  ═══════════════════════════════════════════════════════════════════════

   function Get_Plugin (ID : String) return Plugin_Access is
      Idx : constant Natural := Find_Plugin_Index (ID);
   begin
      if Idx = 0 then
         return null;
      end if;
      return Plugins (Idx).Impl;
   end Get_Plugin;

   function Get_Plugin_By_Type (PM : Package_Manager_Type) return Plugin_Access is
   begin
      for I in 1 .. Plugin_Count loop
         if Plugins (I).Meta.PM_Type = PM and then
            Plugins (I).Meta.Status = Status_Available
         then
            return Plugins (I).Impl;
         end if;
      end loop;
      return null;
   end Get_Plugin_By_Type;

   function Get_Available_Plugins return Natural is
      Count : Natural := 0;
   begin
      for I in 1 .. Plugin_Count loop
         if Plugins (I).Meta.Status = Status_Available then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Get_Available_Plugins;

   function Get_Plugin_Metadata (ID : String) return Plugin_Metadata is
      Idx : constant Natural := Find_Plugin_Index (ID);
   begin
      if Idx = 0 then
         return (others => <>);  --  Empty metadata
      end if;
      return Plugins (Idx).Meta;
   end Get_Plugin_Metadata;

   function Get_Best_Plugin_For (Required : Capability_Set) return Plugin_Access is
      Best_Plugin : Plugin_Access := null;
      Best_Priority : Plugin_Priority := 0;
   begin
      for I in 1 .. Plugin_Count loop
         declare
            P : Plugin_Entry renames Plugins (I);
            Matches : Boolean := True;
         begin
            --  Skip unavailable/disabled plugins
            if P.Meta.Status /= Status_Available or not P.Active then
               Matches := False;
            else
               --  Check all required capabilities
               for Cap in Plugin_Capability loop
                  if Required (Cap) and not P.Meta.Capabilities (Cap) then
                     Matches := False;
                     exit;
                  end if;
               end loop;
            end if;

            --  Update best if this one is better
            if Matches and P.Meta.Priority > Best_Priority then
               Best_Plugin := P.Impl;
               Best_Priority := P.Meta.Priority;
            end if;
         end;
      end loop;
      return Best_Plugin;
   end Get_Best_Plugin_For;

   function Get_Plugins_With_Capability (Cap : Plugin_Capability) return Natural is
      Count : Natural := 0;
   begin
      for I in 1 .. Plugin_Count loop
         if Plugins (I).Meta.Capabilities (Cap) and
            Plugins (I).Meta.Status = Status_Available
         then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Get_Plugins_With_Capability;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Status Management
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Enable_Plugin (ID : String) is
      Idx : constant Natural := Find_Plugin_Index (ID);
   begin
      if Idx /= 0 then
         Plugins (Idx).Active := True;
      end if;
   end Enable_Plugin;

   procedure Disable_Plugin (ID : String) is
      Idx : constant Natural := Find_Plugin_Index (ID);
   begin
      if Idx /= 0 then
         Plugins (Idx).Active := False;
      end if;
   end Disable_Plugin;

   function Is_Plugin_Enabled (ID : String) return Boolean is
      Idx : constant Natural := Find_Plugin_Index (ID);
   begin
      if Idx = 0 then
         return False;
      end if;
      return Plugins (Idx).Active;
   end Is_Plugin_Enabled;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Built-in Plugin Factories
   --  ═══════════════════════════════════════════════════════════════════════

   --  Wrapper type for built-in plugins
   type Builtin_Plugin is new Plugin with record
      Meta    : Plugin_Metadata;
      Backend : Backend_Access := null;
   end record;

   overriding function Get_Metadata (Self : Builtin_Plugin) return Plugin_Metadata is
     (Self.Meta);

   overriding function Get_Backend (Self : Builtin_Plugin) return Backend_Access is
     (Self.Backend);

   overriding function Check_Available (Self : Builtin_Plugin) return Boolean is
   begin
      --  Check required commands
      declare
         Cmds : constant String := To_String (Self.Meta.Required_Commands);
         Start : Positive := Cmds'First;
         Pos   : Natural;
      begin
         while Start <= Cmds'Last loop
            Pos := Start;
            while Pos <= Cmds'Last and then Cmds (Pos) /= ' ' loop
               Pos := Pos + 1;
            end loop;
            if Pos > Start then
               if not Command_Exists (Cmds (Start .. Pos - 1)) then
                  return False;
               end if;
            end if;
            Start := Pos + 1;
         end loop;
      end;
      return True;
   end Check_Available;

   overriding procedure Initialize (Self : in Out Builtin_Plugin) is
   begin
      null;  --  Built-in plugins need no initialization
   end Initialize;

   overriding procedure Shutdown (Self : in Out Builtin_Plugin) is
   begin
      null;  --  Built-in plugins need no shutdown
   end Shutdown;

   function Create_Guix_Plugin return Plugin_Access is
      P : constant access Builtin_Plugin := new Builtin_Plugin;
   begin
      P.Meta :=
        (ID          => To_Unbounded_String ("guix"),
         Name        => To_Unbounded_String ("GNU Guix"),
         Version     => To_Unbounded_String ("1.0.0"),
         Description => To_Unbounded_String ("GNU Guix functional package manager"),
         PM_Type     => Guix,
         Plugin_Kind => Plugin_Builtin,
         Status      => Status_Unavailable,
         Priority    => 90,  --  High priority - native transactions
         Capabilities =>
           (Cap_Install | Cap_Remove | Cap_Upgrade | Cap_Search |
            Cap_Query | Cap_Transactions | Cap_Native_Rollback |
            Cap_Dry_Run | Cap_Autoremove | Cap_Cache_Clean |
            Cap_Dependencies | Cap_History => True,
            others => False),
         Required_Commands => To_Unbounded_String ("guix"),
         Config_Path => To_Unbounded_String (""),
         Has_Native_Recovery => True,
         Preferred_Snapshot => Native);
      return Plugin_Access (P);
   end Create_Guix_Plugin;

   function Create_Nix_Plugin return Plugin_Access is
      P : constant access Builtin_Plugin := new Builtin_Plugin;
   begin
      P.Meta :=
        (ID          => To_Unbounded_String ("nix"),
         Name        => To_Unbounded_String ("Nix"),
         Version     => To_Unbounded_String ("1.0.0"),
         Description => To_Unbounded_String ("Nix package manager with generations"),
         PM_Type     => Nix,
         Plugin_Kind => Plugin_Builtin,
         Status      => Status_Unavailable,
         Priority    => 90,  --  High priority - native transactions
         Capabilities =>
           (Cap_Install | Cap_Remove | Cap_Upgrade | Cap_Search |
            Cap_Query | Cap_Transactions | Cap_Native_Rollback |
            Cap_Dry_Run | Cap_Autoremove | Cap_Cache_Clean |
            Cap_Dependencies | Cap_History => True,
            others => False),
         Required_Commands => To_Unbounded_String ("nix-env"),
         Config_Path => To_Unbounded_String (""),
         Has_Native_Recovery => True,
         Preferred_Snapshot => Native);
      return Plugin_Access (P);
   end Create_Nix_Plugin;

   function Create_Apt_Plugin return Plugin_Access is
      P : constant access Builtin_Plugin := new Builtin_Plugin;
   begin
      P.Meta :=
        (ID          => To_Unbounded_String ("apt"),
         Name        => To_Unbounded_String ("APT"),
         Version     => To_Unbounded_String ("1.0.0"),
         Description => To_Unbounded_String ("Debian/Ubuntu package manager"),
         PM_Type     => APT,
         Plugin_Kind => Plugin_Builtin,
         Status      => Status_Unavailable,
         Priority    => 70,
         Capabilities =>
           (Cap_Install | Cap_Remove | Cap_Upgrade | Cap_Search |
            Cap_Query | Cap_Dry_Run | Cap_Pinning | Cap_Hold |
            Cap_Autoremove | Cap_Cache_Clean | Cap_Verify |
            Cap_Dependencies | Cap_Provides | Cap_Files => True,
            others => False),
         Required_Commands => To_Unbounded_String ("apt apt-get dpkg"),
         Config_Path => To_Unbounded_String (""),
         Has_Native_Recovery => False,
         Preferred_Snapshot => Btrfs);  --  Prefer btrfs snapshots
      return Plugin_Access (P);
   end Create_Apt_Plugin;

   function Create_DNF_Plugin return Plugin_Access is
      P : constant access Builtin_Plugin := new Builtin_Plugin;
   begin
      P.Meta :=
        (ID          => To_Unbounded_String ("dnf"),
         Name        => To_Unbounded_String ("DNF"),
         Version     => To_Unbounded_String ("1.0.0"),
         Description => To_Unbounded_String ("Fedora/RHEL package manager"),
         PM_Type     => DNF,
         Plugin_Kind => Plugin_Builtin,
         Status      => Status_Unavailable,
         Priority    => 70,
         Capabilities =>
           (Cap_Install | Cap_Remove | Cap_Upgrade | Cap_Search |
            Cap_Query | Cap_Dry_Run | Cap_Pinning |
            Cap_Autoremove | Cap_Cache_Clean | Cap_Verify |
            Cap_Dependencies | Cap_Provides | Cap_Files |
            Cap_History => True,
            others => False),
         Required_Commands => To_Unbounded_String ("dnf rpm"),
         Config_Path => To_Unbounded_String (""),
         Has_Native_Recovery => False,
         Preferred_Snapshot => Btrfs);
      return Plugin_Access (P);
   end Create_DNF_Plugin;

   function Create_Pacman_Plugin return Plugin_Access is
      P : constant access Builtin_Plugin := new Builtin_Plugin;
   begin
      P.Meta :=
        (ID          => To_Unbounded_String ("pacman"),
         Name        => To_Unbounded_String ("Pacman"),
         Version     => To_Unbounded_String ("1.0.0"),
         Description => To_Unbounded_String ("Arch Linux package manager"),
         PM_Type     => Pacman,
         Plugin_Kind => Plugin_Builtin,
         Status      => Status_Unavailable,
         Priority    => 70,
         Capabilities =>
           (Cap_Install | Cap_Remove | Cap_Upgrade | Cap_Search |
            Cap_Query | Cap_Dry_Run | Cap_Autoremove | Cap_Cache_Clean |
            Cap_Verify | Cap_Dependencies | Cap_Provides | Cap_Files => True,
            others => False),
         Required_Commands => To_Unbounded_String ("pacman"),
         Config_Path => To_Unbounded_String (""),
         Has_Native_Recovery => False,
         Preferred_Snapshot => Btrfs);
      return Plugin_Access (P);
   end Create_Pacman_Plugin;

   function Create_Flatpak_Plugin return Plugin_Access is
      P : constant access Builtin_Plugin := new Builtin_Plugin;
   begin
      P.Meta :=
        (ID          => To_Unbounded_String ("flatpak"),
         Name        => To_Unbounded_String ("Flatpak"),
         Version     => To_Unbounded_String ("1.0.0"),
         Description => To_Unbounded_String ("Flatpak sandboxed applications"),
         PM_Type     => Flatpak,
         Plugin_Kind => Plugin_Builtin,
         Status      => Status_Unavailable,
         Priority    => 60,  --  Lower priority than system PM
         Capabilities =>
           (Cap_Install | Cap_Remove | Cap_Upgrade | Cap_Search |
            Cap_Query | Cap_Autoremove => True,
            others => False),
         Required_Commands => To_Unbounded_String ("flatpak"),
         Config_Path => To_Unbounded_String (""),
         Has_Native_Recovery => False,
         Preferred_Snapshot => None);  --  Flatpak is sandboxed, low risk
      return Plugin_Access (P);
   end Create_Flatpak_Plugin;

   procedure Register_Builtin_Plugins is
   begin
      Register_Plugin (Create_Guix_Plugin);
      Register_Plugin (Create_Nix_Plugin);
      Register_Plugin (Create_Apt_Plugin);
      Register_Plugin (Create_DNF_Plugin);
      Register_Plugin (Create_Pacman_Plugin);
      Register_Plugin (Create_Flatpak_Plugin);
   end Register_Builtin_Plugins;

end Plugin_Registry;
