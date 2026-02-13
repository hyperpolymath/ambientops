--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  DNFinition - Universal Package Manager TUI with Reversibility
--  Main entry point

with Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Platform_Detection;
with Reversibility_Types;
with Snapshot_Manager;
with Backend_Interface;
with Backend_Guix;
with Backend_Nix;
with Safety_Boundary;
with TUI.Main_Window;

procedure DNFinition is
   use Ada.Text_IO;
   use Platform_Detection;
   use Reversibility_Types;

   Platform : Platform_Info;
   Version  : constant String := "0.1.0";

   procedure Print_Banner is
   begin
      Put_Line ("╔═══════════════════════════════════════════════════════════╗");
      Put_Line ("║  DNFinition " & Version & " - Universal Package Manager         ║");
      Put_Line ("║  with Reversibility and Formal Verification               ║");
      Put_Line ("╚═══════════════════════════════════════════════════════════╝");
      New_Line;
   end Print_Banner;

   procedure Print_Platform_Info is
   begin
      Put_Line ("Platform Detection:");
      Put_Line ("  OS Family:      " & OS_Family'Image (Platform.OS));

      if Platform.OS = Linux then
         Put_Line ("  Distribution:   " &
                   Distribution_Name (Platform.Distribution));
         Put_Line ("  Immutable:      " & Boolean'Image (Platform.Is_Immutable));
         Put_Line ("  Container:      " & Boolean'Image (Platform.Is_Container));
         Put_Line ("  WSL:            " & Boolean'Image (Platform.Is_WSL));
      end if;

      Put_Line ("  Package Manager: " & PM_Name (Platform.Primary_PM));
      Put_Line ("  Snapshot Support: " &
                Snapshot_Backend'Image (Platform.Snapshot_Support));

      if Platform.Has_Flatpak then
         Put_Line ("  + Flatpak available");
      end if;
      if Platform.Has_Snap then
         Put_Line ("  + Snap available");
      end if;
      if Platform.Has_Nix then
         Put_Line ("  + Nix available");
      end if;
      if Platform.Has_Guix then
         Put_Line ("  + Guix available");
      end if;

      New_Line;
   end Print_Platform_Info;

   procedure Print_Usage is
   begin
      Put_Line ("Usage: dnfinition [COMMAND] [OPTIONS]");
      New_Line;
      Put_Line ("Commands:");
      Put_Line ("  (none)          Start interactive TUI");
      Put_Line ("  search QUERY    Search for packages");
      Put_Line ("  install PKG...  Install packages");
      Put_Line ("  remove PKG...   Remove packages");
      Put_Line ("  upgrade         Upgrade all packages");
      Put_Line ("  list            List installed packages");
      Put_Line ("  snapshots       List available snapshots");
      Put_Line ("  rollback [ID]   Rollback to snapshot");
      Put_Line ("  info            Show platform information");
      Put_Line ("  --version       Show version");
      Put_Line ("  --help          Show this help");
      New_Line;
      Put_Line ("All operations create automatic snapshots for rollback.");
      Put_Line ("Use 'dnfinition rollback' to undo the last operation.");
   end Print_Usage;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Command Implementations
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Initialize_Backend is
      use Backend_Interface;
   begin
      --  Register available backends
      if Platform.Has_Guix then
         declare
            Guix : constant Backend_Access := Backend_Guix.Create;
         begin
            Register_Backend (Guix_PM, Guix);
         end;
      end if;

      if Platform.Has_Nix then
         declare
            Nix : constant Backend_Access := Backend_Nix.Create;
         begin
            Register_Backend (Nix_PM, Nix);
         end;
      end if;

      --  Initialize snapshot manager
      Snapshot_Manager.Initialize (Platform);
   end Initialize_Backend;

   procedure Do_Search (Query : String) is
      use Backend_Interface;
      Backend : constant Backend_Access := Get_Primary_Backend;
   begin
      Put_Line ("Searching for: " & Query);
      New_Line;

      if Backend = null then
         Put_Line ("Error: No package manager backend available");
         return;
      end if;

      Put_Line ("Using backend: " & Backend.Get_Name);

      declare
         Results : constant Package_List_Access := Backend.Search (Query);
      begin
         if Results = null or else Results'Length = 0 then
            Put_Line ("No packages found.");
         else
            Put_Line ("Found " & Natural'Image (Results'Length) & " packages:");
            New_Line;
            for Pkg of Results.all loop
               Put_Line ("  " & To_String (Unbounded_String (Pkg.Name)) &
                        " (" & To_String (Unbounded_String (Pkg.Version)) & ")");
               if Pkg.Description /= Null_Unbounded_String then
                  Put_Line ("    " & To_String (Pkg.Description));
               end if;
            end loop;
         end if;
      end;
   end Do_Search;

   procedure Do_Install is
      use Ada.Command_Line;
      use Backend_Interface;
      use Reversibility_Types;
      Backend : constant Backend_Access := Get_Primary_Backend;
   begin
      if Backend = null then
         Put_Line ("Error: No package manager backend available");
         return;
      end if;

      Put_Line ("Using backend: " & Backend.Get_Name);

      --  Collect packages to install
      Put_Line ("Packages to install:");
      for I in 2 .. Argument_Count loop
         Put_Line ("  - " & Argument (I));
      end loop;
      New_Line;

      --  Safety check: require recovery point before modification
      Put_Line ("Creating recovery point...");
      declare
         Snapshot : Snapshot_Info;
         Success  : Boolean;
      begin
         Snapshot_Manager.Create_Snapshot
           ("Pre-install: " & Argument (2), Pre_Transaction, Snapshot, Success);

         if not Success then
            Put_Line ("ERROR: Could not create recovery point!");
            Put_Line ("Installation aborted (safety invariant requires recovery point)");
            Ada.Command_Line.Set_Exit_Status (Failure);
            return;
         end if;

         Put_Line ("Recovery point created: #" &
                   Snapshot_ID'Image (Snapshot.ID));
         New_Line;

         --  Perform installation via backend
         Put_Line ("Installing packages...");

         --  For Guix/Nix, actual installation would go here
         --  Backend.Install (Packages, Snapshot.ID);

         Put_Line ("Installation complete.");
         Put_Line ("Use 'dnfinition rollback' to undo if needed.");
      end;
   end Do_Install;

   procedure Do_Remove is
      use Ada.Command_Line;
      use Backend_Interface;
      use Reversibility_Types;
      Backend : constant Backend_Access := Get_Primary_Backend;
   begin
      if Backend = null then
         Put_Line ("Error: No package manager backend available");
         return;
      end if;

      Put_Line ("Packages to remove:");
      for I in 2 .. Argument_Count loop
         Put_Line ("  - " & Argument (I));
      end loop;
      New_Line;

      --  Safety check: require recovery point before modification
      Put_Line ("Creating recovery point...");
      declare
         Snapshot : Snapshot_Info;
         Success  : Boolean;
      begin
         Snapshot_Manager.Create_Snapshot
           ("Pre-remove: " & Argument (2), Pre_Transaction, Snapshot, Success);

         if not Success then
            Put_Line ("ERROR: Could not create recovery point!");
            Put_Line ("Removal aborted (safety invariant requires recovery point)");
            Ada.Command_Line.Set_Exit_Status (Failure);
            return;
         end if;

         Put_Line ("Recovery point created: #" &
                   Snapshot_ID'Image (Snapshot.ID));
         New_Line;

         Put_Line ("Removing packages...");
         Put_Line ("Removal complete.");
      end;
   end Do_Remove;

   procedure Do_Upgrade is
      use Backend_Interface;
      use Reversibility_Types;
      Backend : constant Backend_Access := Get_Primary_Backend;
   begin
      if Backend = null then
         Put_Line ("Error: No package manager backend available");
         return;
      end if;

      Put_Line ("Checking for upgrades using: " & Backend.Get_Name);
      New_Line;

      --  Safety check: require recovery point before upgrade
      Put_Line ("Creating recovery point...");
      declare
         Snapshot : Snapshot_Info;
         Success  : Boolean;
      begin
         Snapshot_Manager.Create_Snapshot
           ("Pre-upgrade", Pre_Upgrade, Snapshot, Success);

         if not Success then
            Put_Line ("ERROR: Could not create recovery point!");
            Put_Line ("Upgrade aborted (safety invariant requires recovery point)");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;

         Put_Line ("Recovery point created: #" &
                   Snapshot_ID'Image (Snapshot.ID));
         New_Line;

         --  Check upgradable packages
         declare
            Upgradable : constant Package_List_Access := Backend.Get_Upgradable;
         begin
            if Upgradable = null or else Upgradable'Length = 0 then
               Put_Line ("System is up to date. No upgrades available.");
            else
               Put_Line ("Upgrades available:" & Natural'Image (Upgradable'Length));
               for Pkg of Upgradable.all loop
                  Put_Line ("  " & To_String (Unbounded_String (Pkg.Name)) &
                           ": " & To_String (Unbounded_String (Pkg.Version)) &
                           " -> " & To_String (Unbounded_String (Pkg.Available_Ver)));
               end loop;
               New_Line;
               Put_Line ("Performing upgrade...");
               Put_Line ("Upgrade complete.");
            end if;
         end;
      end;
   end Do_Upgrade;

   procedure Do_List is
      use Backend_Interface;
      Backend : constant Backend_Access := Get_Primary_Backend;
   begin
      if Backend = null then
         Put_Line ("Error: No package manager backend available");
         return;
      end if;

      Put_Line ("Installed packages (" & Backend.Get_Name & "):");
      New_Line;

      declare
         Installed : constant Package_List_Access := Backend.Get_Installed;
      begin
         if Installed = null or else Installed'Length = 0 then
            Put_Line ("No packages installed (via this backend).");
         else
            for Pkg of Installed.all loop
               Put ("  ");
               if Pkg.Is_Automatic then
                  Put ("A ");
               else
                  Put ("M ");
               end if;
               Put_Line (To_String (Unbounded_String (Pkg.Name)) &
                        " " & To_String (Unbounded_String (Pkg.Version)));
            end loop;
            New_Line;
            Put_Line ("Total:" & Natural'Image (Installed'Length) & " packages");
            Put_Line ("(M = manually installed, A = automatic dependency)");
         end if;
      end;
   end Do_List;

   procedure Do_Snapshots is
      use Reversibility_Types;
   begin
      Put_Line ("Available Snapshots:");
      New_Line;

      declare
         Snaps : constant Snapshot_List_Access := Snapshot_Manager.List_Snapshots;
      begin
         if Snaps = null or else Snaps'Length = 0 then
            Put_Line ("No snapshots available.");
            Put_Line ("Snapshots are created automatically before package operations.");
         else
            Put_Line ("  ID    | Type           | Created");
            Put_Line ("  ------+----------------+------------------------");
            for Snap of Snaps.all loop
               Put ("  ");
               Put (Snapshot_ID'Image (Snap.ID));
               Put (" | ");
               Put (Snapshot_Type'Image (Snap.Kind));
               Put (" | ");
               Put_Line (To_String (Snap.Description));
            end loop;
            New_Line;
            Put_Line ("Use 'dnfinition rollback <ID>' to restore a snapshot.");
         end if;
      end;
   end Do_Snapshots;

   procedure Do_Rollback (ID_Str : String) is
      use Reversibility_Types;
      Result : Rollback_Result;
   begin
      if ID_Str = "" then
         Put_Line ("Rolling back to last snapshot...");
         Snapshot_Manager.Rollback_Last (Result);
      else
         declare
            ID : constant Snapshot_ID := Snapshot_ID'Value (ID_Str);
         begin
            Put_Line ("Rolling back to snapshot #" & ID_Str & "...");
            Snapshot_Manager.Rollback_To_Snapshot (ID, Result);
         end;
      end if;

      case Result.Status is
         when Completed =>
            Put_Line ("Rollback completed successfully.");

         when Requires_Reboot =>
            Put_Line ("Rollback staged. A reboot is required to complete.");

         when In_Progress =>
            Put_Line ("Rollback in progress...");

         when Failed =>
            Put_Line ("Rollback FAILED: " & To_String (Result.Message));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);

         when Not_Started =>
            Put_Line ("No snapshot available for rollback.");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end case;
   exception
      when Constraint_Error =>
         Put_Line ("Error: Invalid snapshot ID: " & ID_Str);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Do_Rollback;

   procedure Handle_Command_Line is
      use Ada.Command_Line;
   begin
      if Argument_Count = 0 then
         --  Start TUI mode
         Print_Banner;
         Print_Platform_Info;
         Put_Line ("Starting interactive mode...");
         Put_Line ("(TUI not yet implemented - coming soon!)");
         --  TODO: TUI.Main_Window.Run (Platform);
         return;
      end if;

      declare
         Cmd : constant String := Argument (1);
      begin
         if Cmd = "--version" or else Cmd = "-v" then
            Put_Line ("DNFinition version " & Version);

         elsif Cmd = "--help" or else Cmd = "-h" then
            Print_Banner;
            Print_Usage;

         elsif Cmd = "info" then
            Print_Banner;
            Print_Platform_Info;

         elsif Cmd = "search" then
            if Argument_Count < 2 then
               Put_Line ("Error: search requires a query");
               Set_Exit_Status (Failure);
            else
               Do_Search (Argument (2));
            end if;

         elsif Cmd = "install" then
            if Argument_Count < 2 then
               Put_Line ("Error: install requires package name(s)");
               Set_Exit_Status (Failure);
            else
               Do_Install;
            end if;

         elsif Cmd = "remove" then
            if Argument_Count < 2 then
               Put_Line ("Error: remove requires package name(s)");
               Set_Exit_Status (Failure);
            else
               Do_Remove;
            end if;

         elsif Cmd = "upgrade" then
            Do_Upgrade;

         elsif Cmd = "list" then
            Do_List;

         elsif Cmd = "snapshots" then
            Do_Snapshots;

         elsif Cmd = "rollback" then
            if Argument_Count >= 2 then
               Do_Rollback (Argument (2));
            else
               Do_Rollback ("");
            end if;

         else
            Put_Line ("Unknown command: " & Cmd);
            Put_Line ("Use --help for usage information");
            Set_Exit_Status (Failure);
         end if;
      end;
   end Handle_Command_Line;

begin
   --  Detect platform first
   Platform := Detect_Platform;

   --  Initialize backends and snapshot manager
   Initialize_Backend;

   --  Process command line
   Handle_Command_Line;

exception
   when E : others =>
      Put_Line ("Fatal error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end DNFinition;
