--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Platform Detection - Identifies OS, distribution, and package managers
--  This module uses SPARK for formal verification of platform detection

pragma SPARK_Mode (On);

package Platform_Detection is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Operating System Families
   --  ═══════════════════════════════════════════════════════════════════════

   type OS_Family is
     (Unknown,
      Linux,
      Darwin,      --  macOS
      FreeBSD,
      OpenBSD,
      NetBSD,
      DragonflyBSD,
      Solaris,
      Windows);

   --  ═══════════════════════════════════════════════════════════════════════
   --  Linux Distributions
   --  ═══════════════════════════════════════════════════════════════════════

   type Linux_Distribution is
     (Unknown_Linux,
      --  RPM-based
      Fedora,
      Fedora_Silverblue,
      Fedora_Kinoite,
      RHEL,
      Rocky,
      Alma,
      CentOS,
      CentOS_Stream,
      OpenSUSE_Leap,
      OpenSUSE_Tumbleweed,
      SUSE_Enterprise,
      Mageia,
      --  DEB-based
      Debian,
      Ubuntu,
      Linux_Mint,
      Pop_OS,
      Elementary,
      --  Other
      Arch,
      Manjaro,
      EndeavourOS,
      Void,
      Alpine,
      Gentoo,
      NixOS,
      Guix_System,
      Slackware,
      --  Immutable/Specialized
      Fedora_CoreOS,
      RHCOS,           --  Red Hat CoreOS
      Flatcar,
      Talos,
      --  Other/Custom
      Other_Linux);

   --  ═══════════════════════════════════════════════════════════════════════
   --  Package Manager Types
   --  ═══════════════════════════════════════════════════════════════════════

   type Package_Manager_Type is
     (None,
      --  Native Linux
      RPM_OSTree,    --  Fedora Silverblue/Kinoite, CoreOS
      DNF,           --  Fedora, RHEL 8+
      YUM,           --  RHEL 7, CentOS 7
      Zypper,        --  openSUSE, SLE
      APT,           --  Debian, Ubuntu family
      Pacman,        --  Arch family
      XBPS,          --  Void Linux
      APK,           --  Alpine Linux
      Portage,       --  Gentoo
      Nix,           --  NixOS and standalone
      Guix,          --  Guix System and standalone
      Slackpkg,      --  Slackware
      --  BSD
      Pkg_FreeBSD,   --  FreeBSD
      Pkg_Add,       --  OpenBSD
      Pkgin,         --  NetBSD
      --  macOS
      Homebrew,
      MacPorts,
      --  Windows
      Winget,
      Chocolatey,
      Scoop,
      --  Universal/Container
      Flatpak,
      Snap,
      AppImage);     --  Not really a PM but needs tracking

   --  ═══════════════════════════════════════════════════════════════════════
   --  Filesystem Snapshot Support
   --  ═══════════════════════════════════════════════════════════════════════

   type Snapshot_Backend is
     (None,
      Native,        --  Use package manager's native support
      Btrfs,
      ZFS,
      LVM,
      APFS,          --  macOS
      VSS);          --  Windows Volume Shadow Copy

   --  ═══════════════════════════════════════════════════════════════════════
   --  Platform Record - Complete System Description
   --  ═══════════════════════════════════════════════════════════════════════

   type Platform_Info is record
      OS                  : OS_Family := Unknown;
      Distribution        : Linux_Distribution := Unknown_Linux;
      Is_Immutable        : Boolean := False;
      Is_Container        : Boolean := False;
      Is_WSL              : Boolean := False;
      Primary_PM          : Package_Manager_Type := None;
      Has_Flatpak         : Boolean := False;
      Has_Snap            : Boolean := False;
      Has_Nix             : Boolean := False;
      Has_Guix            : Boolean := False;
      Has_Homebrew        : Boolean := False;
      Snapshot_Support    : Snapshot_Backend := None;
      Can_Use_Btrfs       : Boolean := False;
      Can_Use_ZFS         : Boolean := False;
      Can_Use_LVM         : Boolean := False;
   end record;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Detection Functions with SPARK Contracts
   --  ═══════════════════════════════════════════════════════════════════════

   function Detect_Platform return Platform_Info
     with Post => Detect_Platform'Result.OS /= Unknown or else
                  Detect_Platform'Result.Primary_PM = None;
   --  Detect the current platform. If OS is unknown, no PM should be assumed.

   function Detect_OS return OS_Family;
   --  Detect just the OS family

   function Detect_Linux_Distribution return Linux_Distribution
     with Pre => Detect_OS = Linux;
   --  Detect Linux distribution. Must only be called on Linux.

   function Detect_Primary_Package_Manager
     (Platform : Platform_Info) return Package_Manager_Type
     with Post => (if Platform.OS = Unknown
                   then Detect_Primary_Package_Manager'Result = None);
   --  Get the primary package manager for a given platform

   function Detect_Snapshot_Backend
     (Platform : Platform_Info) return Snapshot_Backend
     with Post => (if Platform.Is_Immutable and Platform.Primary_PM = RPM_OSTree
                   then Detect_Snapshot_Backend'Result = Native);
   --  Determine best snapshot backend. rpm-ostree has native support.

   --  ═══════════════════════════════════════════════════════════════════════
   --  Utility Functions
   --  ═══════════════════════════════════════════════════════════════════════

   function Is_Immutable_System (Platform : Platform_Info) return Boolean is
     (Platform.Is_Immutable);

   function Supports_Rollback (Platform : Platform_Info) return Boolean is
     (Platform.Snapshot_Support /= None or else Platform.Is_Immutable);

   function Has_Native_Transactions (PM : Package_Manager_Type) return Boolean is
     (PM in RPM_OSTree | Nix | Guix | Zypper);
   --  These package managers have native transactional/reversible support

   function Distribution_Name (Distro : Linux_Distribution) return String;
   --  Human-readable distribution name

   function PM_Name (PM : Package_Manager_Type) return String;
   --  Human-readable package manager name

end Platform_Detection;
