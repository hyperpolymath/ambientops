--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Strategy_Matrix - Snapshot and backout strategy selection
--
--  This module determines the optimal recovery strategy based on:
--  1. Package manager capabilities (native transactions, rollback)
--  2. Available filesystem features (btrfs, ZFS, LVM)
--  3. Operation type and risk level
--  4. System configuration (immutable, container, etc.)
--
--  The strategy matrix ensures we always have a recovery path before
--  performing any modifying operation.

pragma SPARK_Mode (On);

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Platform_Detection;    use Platform_Detection;
with Plugin_Registry;       use Plugin_Registry;
with Reversibility_Types;   use Reversibility_Types;

package Strategy_Matrix is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Operation Risk Levels
   --  ═══════════════════════════════════════════════════════════════════════

   type Risk_Level is
     (Risk_None,       --  Read-only operations
      Risk_Low,        --  Install user packages
      Risk_Medium,     --  Remove packages, upgrade specific
      Risk_High,       --  System upgrade, kernel changes
      Risk_Critical);  --  Bootloader, system files

   --  ═══════════════════════════════════════════════════════════════════════
   --  Recovery Strategy Types
   --  ═══════════════════════════════════════════════════════════════════════

   type Recovery_Strategy is
     (Strategy_None,           --  No recovery needed (read-only)
      Strategy_Native,         --  Use PM's native recovery (Guix/Nix generations)
      Strategy_Btrfs_Snapshot, --  Btrfs subvolume snapshot
      Strategy_ZFS_Snapshot,   --  ZFS snapshot
      Strategy_LVM_Snapshot,   --  LVM thin snapshot
      Strategy_Snapper,        --  Snapper (openSUSE integration)
      Strategy_Ostree,         --  rpm-ostree deployment
      Strategy_APFS,           --  macOS APFS snapshot
      Strategy_VSS,            --  Windows Volume Shadow Copy
      Strategy_Transaction_Log,--  Fallback: log-based recovery
      Strategy_Manual);        --  User must handle recovery

   type Strategy_Confidence is
     (Confidence_Proven,       --  Formally verified or extensively tested
      Confidence_High,         --  Well-tested, known reliable
      Confidence_Medium,       --  Generally works, some edge cases
      Confidence_Low,          --  Experimental or limited testing
      Confidence_Unknown);     --  Not tested

   --  ═══════════════════════════════════════════════════════════════════════
   --  Backout Capability
   --  ═══════════════════════════════════════════════════════════════════════

   type Backout_Capability is
     (Backout_Instant,         --  Immediate rollback (generation switch)
      Backout_Fast,            --  Quick restore (< 1 minute)
      Backout_Slow,            --  Full restore needed (minutes)
      Backout_Reboot,          --  Requires reboot
      Backout_Manual,          --  Manual intervention required
      Backout_None);           --  Cannot backout

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Recommendation
   --  ═══════════════════════════════════════════════════════════════════════

   type Strategy_Recommendation is record
      --  Primary strategy
      Primary         : Recovery_Strategy := Strategy_Transaction_Log;
      Primary_Confidence : Strategy_Confidence := Confidence_Unknown;

      --  Fallback if primary fails
      Fallback        : Recovery_Strategy := Strategy_Manual;
      Fallback_Confidence : Strategy_Confidence := Confidence_Unknown;

      --  Backout capability
      Backout         : Backout_Capability := Backout_Manual;
      Requires_Reboot : Boolean := False;

      --  Additional information
      Description     : Unbounded_String;
      Warnings        : Unbounded_String;
      Estimated_Time  : Natural := 0;  --  Seconds for recovery

      --  Applicability
      Applicable      : Boolean := False;
      Reason          : Unbounded_String;  --  Why this strategy was chosen
   end record;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Matrix Entry
   --  ═══════════════════════════════════════════════════════════════════════

   --  A matrix entry maps (PM capabilities × Filesystem × Risk) → Strategy

   type Matrix_Entry is record
      --  Input conditions
      PM_Type         : Package_Manager_Type := None;
      Has_Native_Recovery : Boolean := False;
      Snapshot_Backend : Snapshot_Backend := None;
      Risk            : Risk_Level := Risk_Medium;

      --  Output strategy
      Recommendation  : Strategy_Recommendation;
   end record;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Selection Functions
   --  ═══════════════════════════════════════════════════════════════════════

   function Get_Strategy
     (Platform : Platform_Info;
      PM       : Package_Manager_Type;
      Risk     : Risk_Level) return Strategy_Recommendation
     with Post => Get_Strategy'Result.Applicable or
                  Get_Strategy'Result.Primary = Strategy_Manual;
   --  Get recommended strategy for given conditions

   function Get_Strategy_For_Plugin
     (Meta : Plugin_Metadata;
      Risk : Risk_Level) return Strategy_Recommendation;
   --  Get strategy based on plugin metadata

   function Get_Best_Recovery_Backend
     (Platform : Platform_Info) return Snapshot_Backend
     with Post => Get_Best_Recovery_Backend'Result /= None or
                  not Supports_Rollback (Platform);
   --  Determine best snapshot backend for this platform

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Matrix (The Core Decision Table)
   --  ═══════════════════════════════════════════════════════════════════════

   --  This is the strategy matrix that encodes all recovery strategies.
   --  Format: (PM, Has_Native, Snapshot_Backend, Risk) → Strategy

   --  Row 1: Guix/Nix with native recovery (BEST CASE)
   --  - Always use native generation-based recovery
   --  - Instant backout via generation switch
   --  - Works for all risk levels

   --  Row 2: rpm-ostree (Fedora Silverblue, CoreOS)
   --  - Native deployment-based recovery
   --  - Requires reboot for backout
   --  - Excellent for system-level changes

   --  Row 3: Traditional PM + Btrfs
   --  - Use btrfs snapshots
   --  - Fast backout for most operations
   --  - May require reboot for system-level

   --  Row 4: Traditional PM + ZFS
   --  - Use ZFS snapshots
   --  - Similar to btrfs strategy
   --  - Excellent data integrity

   --  Row 5: Traditional PM + LVM
   --  - Use LVM thin snapshots
   --  - Slower than btrfs/ZFS
   --  - Wide compatibility

   --  Row 6: Traditional PM + No Snapshot
   --  - Transaction log only
   --  - Manual recovery if needed
   --  - Higher risk, requires caution

   function Lookup_Strategy
     (PM_Type         : Package_Manager_Type;
      Has_Native      : Boolean;
      Snapshot        : Snapshot_Backend;
      Risk            : Risk_Level) return Strategy_Recommendation;
   --  Direct matrix lookup

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Validation
   --  ═══════════════════════════════════════════════════════════════════════

   function Validate_Strategy
     (Strat    : Strategy_Recommendation;
      Platform : Platform_Info) return Boolean;
   --  Check if a strategy is actually usable on this platform

   function Strategy_Meets_Risk
     (Strat : Strategy_Recommendation;
      Risk  : Risk_Level) return Boolean;
   --  Check if strategy provides adequate protection for risk level

   --  ═══════════════════════════════════════════════════════════════════════
   --  Human-Readable Descriptions
   --  ═══════════════════════════════════════════════════════════════════════

   function Strategy_Name (S : Recovery_Strategy) return String;
   function Risk_Name (R : Risk_Level) return String;
   function Backout_Description (B : Backout_Capability) return String;
   function Confidence_Description (C : Strategy_Confidence) return String;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Execution
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Execute_Pre_Operation_Strategy
     (Strat   : Strategy_Recommendation;
      Desc    : String;
      Success : out Boolean;
      Point   : out Snapshot_ID)
     with Pre  => Strat.Applicable,
          Post => (if Success then Valid_Snapshot (Point));
   --  Execute recovery point creation based on strategy

   procedure Execute_Backout
     (Strat   : Strategy_Recommendation;
      Point   : Snapshot_ID;
      Result  : out Rollback_Status)
     with Pre => Valid_Snapshot (Point);
   --  Execute backout using the strategy's method

end Strategy_Matrix;
