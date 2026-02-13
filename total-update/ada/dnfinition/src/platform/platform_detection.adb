--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

pragma SPARK_Mode (Off);  --  Implementation uses OS calls, not verifiable

with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;

package body Platform_Detection is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Helper Functions
   --  ═══════════════════════════════════════════════════════════════════════

   function File_Exists (Path : String) return Boolean is
   begin
      return Ada.Directories.Exists (Path);
   exception
      when others => return False;
   end File_Exists;

   function Read_File_First_Line (Path : String) return String is
      File : Ada.Text_IO.File_Type;
      Line : String (1 .. 256);
      Last : Natural;
   begin
      if not File_Exists (Path) then
         return "";
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      Ada.Text_IO.Get_Line (File, Line, Last);
      Ada.Text_IO.Close (File);
      return Line (1 .. Last);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return "";
   end Read_File_First_Line;

   function Command_Exists (Cmd : String) return Boolean is
      use GNAT.OS_Lib;
   begin
      return Locate_Exec_On_Path (Cmd) /= null;
   end Command_Exists;

   function Contains (Source : String; Pattern : String) return Boolean is
   begin
      return Ada.Strings.Fixed.Index (Source, Pattern) > 0;
   end Contains;

   --  ═══════════════════════════════════════════════════════════════════════
   --  OS Detection
   --  ═══════════════════════════════════════════════════════════════════════

   function Detect_OS return OS_Family is
   begin
      --  Check /proc/version for Linux
      if File_Exists ("/proc/version") then
         return Linux;
      end if;

      --  Check for macOS
      if File_Exists ("/System/Library/CoreServices/SystemVersion.plist") then
         return Darwin;
      end if;

      --  Check for FreeBSD
      if File_Exists ("/etc/freebsd-update.conf") then
         return FreeBSD;
      end if;

      --  Check for OpenBSD
      if File_Exists ("/bsd") and then File_Exists ("/etc/signify") then
         return OpenBSD;
      end if;

      --  Check for NetBSD
      if File_Exists ("/netbsd") then
         return NetBSD;
      end if;

      --  Check for Windows via environment
      if Ada.Environment_Variables.Exists ("SystemRoot") then
         return Windows;
      end if;

      --  Check for Solaris/illumos
      if File_Exists ("/etc/release") then
         declare
            Release : constant String := Read_File_First_Line ("/etc/release");
         begin
            if Contains (Release, "Solaris") or else
               Contains (Release, "illumos") or else
               Contains (Release, "OpenIndiana")
            then
               return Solaris;
            end if;
         end;
      end if;

      return Unknown;
   end Detect_OS;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Linux Distribution Detection
   --  ═══════════════════════════════════════════════════════════════════════

   function Detect_Linux_Distribution return Linux_Distribution is
      OS_Release : constant String := "/etc/os-release";
   begin
      if not File_Exists (OS_Release) then
         return Unknown_Linux;
      end if;

      --  Parse /etc/os-release for ID and VARIANT_ID
      declare
         File    : Ada.Text_IO.File_Type;
         ID      : String (1 .. 64) := (others => ' ');
         Variant : String (1 .. 64) := (others => ' ');
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, OS_Release);

         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line : constant String := Ada.Text_IO.Get_Line (File);
            begin
               if Contains (Line, "ID=") and not Contains (Line, "_ID") then
                  --  Extract ID value
                  ID := (others => ' ');
                  declare
                     Start : constant Natural :=
                       Ada.Strings.Fixed.Index (Line, "=") + 1;
                     Value : constant String :=
                       Line (Start .. Line'Last);
                  begin
                     ID (1 .. Value'Length) := Value;
                  end;
               elsif Contains (Line, "VARIANT_ID=") then
                  --  Extract VARIANT_ID
                  Variant := (others => ' ');
                  declare
                     Start : constant Natural :=
                       Ada.Strings.Fixed.Index (Line, "=") + 1;
                     Value : constant String :=
                       Line (Start .. Line'Last);
                  begin
                     Variant (1 .. Value'Length) := Value;
                  end;
               end if;
            end;
         end loop;

         Ada.Text_IO.Close (File);

         --  Match distributions
         if Contains (ID, "fedora") then
            if Contains (Variant, "silverblue") then
               return Fedora_Silverblue;
            elsif Contains (Variant, "kinoite") then
               return Fedora_Kinoite;
            elsif Contains (Variant, "coreos") then
               return Fedora_CoreOS;
            else
               return Fedora;
            end if;
         elsif Contains (ID, "rhel") then
            return RHEL;
         elsif Contains (ID, "rocky") then
            return Rocky;
         elsif Contains (ID, "almalinux") then
            return Alma;
         elsif Contains (ID, "centos") then
            if Contains (Variant, "stream") then
               return CentOS_Stream;
            else
               return CentOS;
            end if;
         elsif Contains (ID, "opensuse-leap") then
            return OpenSUSE_Leap;
         elsif Contains (ID, "opensuse-tumbleweed") then
            return OpenSUSE_Tumbleweed;
         elsif Contains (ID, "sles") or else Contains (ID, "suse") then
            return SUSE_Enterprise;
         elsif Contains (ID, "debian") then
            return Debian;
         elsif Contains (ID, "ubuntu") then
            return Ubuntu;
         elsif Contains (ID, "linuxmint") then
            return Linux_Mint;
         elsif Contains (ID, "pop") then
            return Pop_OS;
         elsif Contains (ID, "arch") then
            return Arch;
         elsif Contains (ID, "manjaro") then
            return Manjaro;
         elsif Contains (ID, "endeavouros") then
            return EndeavourOS;
         elsif Contains (ID, "void") then
            return Void;
         elsif Contains (ID, "alpine") then
            return Alpine;
         elsif Contains (ID, "gentoo") then
            return Gentoo;
         elsif Contains (ID, "nixos") then
            return NixOS;
         elsif Contains (ID, "guix") then
            return Guix_System;
         elsif Contains (ID, "slackware") then
            return Slackware;
         else
            return Other_Linux;
         end if;

      exception
         when others =>
            return Unknown_Linux;
      end;
   end Detect_Linux_Distribution;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Package Manager Detection
   --  ═══════════════════════════════════════════════════════════════════════

   function Detect_Primary_Package_Manager
     (Platform : Platform_Info) return Package_Manager_Type
   is
   begin
      case Platform.OS is
         when Linux =>
            case Platform.Distribution is
               when Fedora_Silverblue | Fedora_Kinoite | Fedora_CoreOS | RHCOS =>
                  return RPM_OSTree;
               when Fedora | RHEL | Rocky | Alma | CentOS_Stream =>
                  return DNF;
               when CentOS =>
                  --  CentOS 7 uses yum, CentOS Stream uses dnf
                  if Command_Exists ("dnf") then
                     return DNF;
                  else
                     return YUM;
                  end if;
               when OpenSUSE_Leap | OpenSUSE_Tumbleweed | SUSE_Enterprise =>
                  return Zypper;
               when Debian | Ubuntu | Linux_Mint | Pop_OS | Elementary =>
                  return APT;
               when Arch | Manjaro | EndeavourOS =>
                  return Pacman;
               when Void =>
                  return XBPS;
               when Alpine =>
                  return APK;
               when Gentoo =>
                  return Portage;
               when NixOS =>
                  return Nix;
               when Guix_System =>
                  return Guix;
               when Slackware =>
                  return Slackpkg;
               when others =>
                  return None;
            end case;

         when FreeBSD | DragonflyBSD =>
            return Pkg_FreeBSD;

         when OpenBSD =>
            return Pkg_Add;

         when NetBSD =>
            return Pkgin;

         when Darwin =>
            if Command_Exists ("brew") then
               return Homebrew;
            elsif Command_Exists ("port") then
               return MacPorts;
            else
               return None;
            end if;

         when Windows =>
            if Command_Exists ("winget") then
               return Winget;
            elsif Command_Exists ("choco") then
               return Chocolatey;
            elsif Command_Exists ("scoop") then
               return Scoop;
            else
               return None;
            end if;

         when others =>
            return None;
      end case;
   end Detect_Primary_Package_Manager;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Snapshot Backend Detection
   --  ═══════════════════════════════════════════════════════════════════════

   function Detect_Snapshot_Backend
     (Platform : Platform_Info) return Snapshot_Backend
   is
   begin
      --  rpm-ostree has native deployment-based rollback
      if Platform.Primary_PM = RPM_OSTree then
         return Native;
      end if;

      --  Zypper has native snapper integration on openSUSE
      if Platform.Primary_PM = Zypper then
         return Native;
      end if;

      --  Nix and Guix have native generations
      if Platform.Primary_PM in Nix | Guix then
         return Native;
      end if;

      --  Check for btrfs on root
      if Platform.Can_Use_Btrfs then
         return Btrfs;
      end if;

      --  Check for ZFS
      if Platform.Can_Use_ZFS then
         return ZFS;
      end if;

      --  Check for LVM
      if Platform.Can_Use_LVM then
         return LVM;
      end if;

      --  macOS uses APFS snapshots
      if Platform.OS = Darwin then
         return APFS;
      end if;

      --  Windows uses VSS
      if Platform.OS = Windows then
         return VSS;
      end if;

      return None;
   end Detect_Snapshot_Backend;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Full Platform Detection
   --  ═══════════════════════════════════════════════════════════════════════

   function Detect_Platform return Platform_Info is
      Result : Platform_Info;
   begin
      Result.OS := Detect_OS;

      if Result.OS = Linux then
         Result.Distribution := Detect_Linux_Distribution;

         --  Check for immutable systems
         Result.Is_Immutable := Result.Distribution in
           Fedora_Silverblue | Fedora_Kinoite | Fedora_CoreOS |
           RHCOS | Flatcar | Talos | NixOS | Guix_System;

         --  Check for container environment
         Result.Is_Container := File_Exists ("/.dockerenv") or else
                                File_Exists ("/run/.containerenv") or else
                                File_Exists ("/var/run/.toolboxenv");

         --  Check for WSL
         if File_Exists ("/proc/version") then
            declare
               Version : constant String :=
                 Read_File_First_Line ("/proc/version");
            begin
               Result.Is_WSL := Contains (Version, "Microsoft") or else
                                Contains (Version, "WSL");
            end;
         end if;
      end if;

      --  Detect primary package manager
      Result.Primary_PM := Detect_Primary_Package_Manager (Result);

      --  Check for universal package managers
      Result.Has_Flatpak := Command_Exists ("flatpak");
      Result.Has_Snap := Command_Exists ("snap");
      Result.Has_Nix := Command_Exists ("nix");
      Result.Has_Guix := Command_Exists ("guix");
      Result.Has_Homebrew := Command_Exists ("brew");

      --  Check filesystem snapshot capabilities
      Result.Can_Use_Btrfs := Command_Exists ("btrfs") and then
                              File_Exists ("/proc/filesystems");
      Result.Can_Use_ZFS := Command_Exists ("zfs");
      Result.Can_Use_LVM := Command_Exists ("lvm");

      --  Determine best snapshot backend
      Result.Snapshot_Support := Detect_Snapshot_Backend (Result);

      return Result;
   end Detect_Platform;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Human-Readable Names
   --  ═══════════════════════════════════════════════════════════════════════

   function Distribution_Name (Distro : Linux_Distribution) return String is
   begin
      case Distro is
         when Unknown_Linux => return "Unknown Linux";
         when Fedora => return "Fedora";
         when Fedora_Silverblue => return "Fedora Silverblue";
         when Fedora_Kinoite => return "Fedora Kinoite";
         when RHEL => return "Red Hat Enterprise Linux";
         when Rocky => return "Rocky Linux";
         when Alma => return "AlmaLinux";
         when CentOS => return "CentOS";
         when CentOS_Stream => return "CentOS Stream";
         when OpenSUSE_Leap => return "openSUSE Leap";
         when OpenSUSE_Tumbleweed => return "openSUSE Tumbleweed";
         when SUSE_Enterprise => return "SUSE Linux Enterprise";
         when Mageia => return "Mageia";
         when Debian => return "Debian";
         when Ubuntu => return "Ubuntu";
         when Linux_Mint => return "Linux Mint";
         when Pop_OS => return "Pop!_OS";
         when Elementary => return "elementary OS";
         when Arch => return "Arch Linux";
         when Manjaro => return "Manjaro";
         when EndeavourOS => return "EndeavourOS";
         when Void => return "Void Linux";
         when Alpine => return "Alpine Linux";
         when Gentoo => return "Gentoo";
         when NixOS => return "NixOS";
         when Guix_System => return "Guix System";
         when Slackware => return "Slackware";
         when Fedora_CoreOS => return "Fedora CoreOS";
         when RHCOS => return "Red Hat CoreOS";
         when Flatcar => return "Flatcar Container Linux";
         when Talos => return "Talos Linux";
         when Other_Linux => return "Other Linux";
      end case;
   end Distribution_Name;

   function PM_Name (PM : Package_Manager_Type) return String is
   begin
      case PM is
         when None => return "None";
         when RPM_OSTree => return "rpm-ostree";
         when DNF => return "dnf";
         when YUM => return "yum";
         when Zypper => return "zypper";
         when APT => return "apt";
         when Pacman => return "pacman";
         when XBPS => return "xbps";
         when APK => return "apk";
         when Portage => return "portage";
         when Nix => return "nix";
         when Guix => return "guix";
         when Slackpkg => return "slackpkg";
         when Pkg_FreeBSD => return "pkg";
         when Pkg_Add => return "pkg_add";
         when Pkgin => return "pkgin";
         when Homebrew => return "brew";
         when MacPorts => return "port";
         when Winget => return "winget";
         when Chocolatey => return "choco";
         when Scoop => return "scoop";
         when Flatpak => return "flatpak";
         when Snap => return "snap";
         when AppImage => return "AppImage";
      end case;
   end PM_Name;

end Platform_Detection;
