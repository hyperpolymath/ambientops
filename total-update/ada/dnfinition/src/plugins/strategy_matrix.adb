--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Strategy_Matrix - Implementation of snapshot/backout strategy selection

pragma SPARK_Mode (Off);  --  Implementation uses Snapshot_Manager

with Snapshot_Manager;

package body Strategy_Matrix is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Matrix Lookup Table
   --  ═══════════════════════════════════════════════════════════════════════

   --  The matrix encodes: (PM_Type, Has_Native, Snapshot, Risk) → Strategy
   --
   --  PRIORITY ORDER (higher = preferred):
   --  1. Native PM recovery (Guix/Nix generations) - BEST
   --  2. rpm-ostree deployments
   --  3. Btrfs snapshots
   --  4. ZFS snapshots
   --  5. Snapper (integrates with btrfs/lvm)
   --  6. LVM thin snapshots
   --  7. Transaction log only - FALLBACK

   function Lookup_Strategy
     (PM_Type         : Package_Manager_Type;
      Has_Native      : Boolean;
      Snapshot        : Snapshot_Backend;
      Risk            : Risk_Level) return Strategy_Recommendation
   is
      Rec : Strategy_Recommendation;
   begin
      --  ═══════════════════════════════════════════════════════════════════
      --  CASE 1: Native PM recovery (Guix, Nix, rpm-ostree)
      --  ═══════════════════════════════════════════════════════════════════
      if Has_Native then
         case PM_Type is
            when Guix =>
               Rec := (Primary => Strategy_Native,
                       Primary_Confidence => Confidence_Proven,
                       Fallback => Strategy_Transaction_Log,
                       Fallback_Confidence => Confidence_High,
                       Backout => Backout_Instant,
                       Requires_Reboot => False,
                       Description => To_Unbounded_String
                         ("Guix generation-based recovery"),
                       Warnings => To_Unbounded_String (""),
                       Estimated_Time => 1,
                       Applicable => True,
                       Reason => To_Unbounded_String
                         ("Guix has atomic generations with instant rollback"));

            when Nix =>
               Rec := (Primary => Strategy_Native,
                       Primary_Confidence => Confidence_Proven,
                       Fallback => Strategy_Transaction_Log,
                       Fallback_Confidence => Confidence_High,
                       Backout => Backout_Instant,
                       Requires_Reboot => False,
                       Description => To_Unbounded_String
                         ("Nix generation-based recovery"),
                       Warnings => To_Unbounded_String (""),
                       Estimated_Time => 1,
                       Applicable => True,
                       Reason => To_Unbounded_String
                         ("Nix has atomic generations with instant rollback"));

            when RPM_OSTree =>
               Rec := (Primary => Strategy_Ostree,
                       Primary_Confidence => Confidence_Proven,
                       Fallback => Strategy_Manual,
                       Fallback_Confidence => Confidence_Medium,
                       Backout => Backout_Reboot,
                       Requires_Reboot => True,
                       Description => To_Unbounded_String
                         ("rpm-ostree deployment-based recovery"),
                       Warnings => To_Unbounded_String
                         ("Rollback requires system reboot"),
                       Estimated_Time => 60,  --  Including reboot
                       Applicable => True,
                       Reason => To_Unbounded_String
                         ("rpm-ostree uses immutable deployments"));

            when others =>
               --  Other PM claiming native recovery
               Rec := (Primary => Strategy_Native,
                       Primary_Confidence => Confidence_Medium,
                       Fallback => Strategy_Transaction_Log,
                       Fallback_Confidence => Confidence_High,
                       Backout => Backout_Fast,
                       Requires_Reboot => False,
                       Description => To_Unbounded_String
                         ("Native package manager recovery"),
                       Warnings => To_Unbounded_String (""),
                       Estimated_Time => 10,
                       Applicable => True,
                       Reason => To_Unbounded_String
                         ("Package manager has native transaction support"));
         end case;
         return Rec;
      end if;

      --  ═══════════════════════════════════════════════════════════════════
      --  CASE 2: Filesystem snapshot support
      --  ═══════════════════════════════════════════════════════════════════
      case Snapshot is
         when Btrfs =>
            Rec := (Primary => Strategy_Btrfs_Snapshot,
                    Primary_Confidence => Confidence_High,
                    Fallback => Strategy_Transaction_Log,
                    Fallback_Confidence => Confidence_High,
                    Backout => (if Risk >= Risk_High
                                then Backout_Reboot
                                else Backout_Fast),
                    Requires_Reboot => Risk >= Risk_High,
                    Description => To_Unbounded_String
                      ("Btrfs subvolume snapshot"),
                    Warnings => (if Risk >= Risk_High
                                 then To_Unbounded_String
                                   ("System-level changes may require reboot")
                                 else To_Unbounded_String ("")),
                    Estimated_Time => (if Risk >= Risk_High then 60 else 10),
                    Applicable => True,
                    Reason => To_Unbounded_String
                      ("Btrfs provides fast copy-on-write snapshots"));

         when ZFS =>
            Rec := (Primary => Strategy_ZFS_Snapshot,
                    Primary_Confidence => Confidence_High,
                    Fallback => Strategy_Transaction_Log,
                    Fallback_Confidence => Confidence_High,
                    Backout => (if Risk >= Risk_High
                                then Backout_Reboot
                                else Backout_Fast),
                    Requires_Reboot => Risk >= Risk_High,
                    Description => To_Unbounded_String
                      ("ZFS snapshot"),
                    Warnings => (if Risk >= Risk_High
                                 then To_Unbounded_String
                                   ("System-level changes may require reboot")
                                 else To_Unbounded_String ("")),
                    Estimated_Time => (if Risk >= Risk_High then 60 else 5),
                    Applicable => True,
                    Reason => To_Unbounded_String
                      ("ZFS provides enterprise-grade snapshots with checksumming"));

         when LVM =>
            Rec := (Primary => Strategy_LVM_Snapshot,
                    Primary_Confidence => Confidence_Medium,
                    Fallback => Strategy_Transaction_Log,
                    Fallback_Confidence => Confidence_High,
                    Backout => Backout_Slow,
                    Requires_Reboot => Risk >= Risk_Medium,
                    Description => To_Unbounded_String
                      ("LVM thin snapshot"),
                    Warnings => To_Unbounded_String
                      ("LVM snapshots may require more time to restore"),
                    Estimated_Time => 120,
                    Applicable => True,
                    Reason => To_Unbounded_String
                      ("LVM provides snapshots on traditional filesystems"));

         when Native =>
            --  Already handled above
            null;

         when APFS =>
            Rec := (Primary => Strategy_APFS,
                    Primary_Confidence => Confidence_Medium,
                    Fallback => Strategy_Transaction_Log,
                    Fallback_Confidence => Confidence_High,
                    Backout => Backout_Fast,
                    Requires_Reboot => Risk >= Risk_High,
                    Description => To_Unbounded_String
                      ("APFS snapshot (Time Machine)"),
                    Warnings => To_Unbounded_String (""),
                    Estimated_Time => 30,
                    Applicable => True,
                    Reason => To_Unbounded_String
                      ("APFS provides native macOS snapshots"));

         when VSS =>
            Rec := (Primary => Strategy_VSS,
                    Primary_Confidence => Confidence_Medium,
                    Fallback => Strategy_Transaction_Log,
                    Fallback_Confidence => Confidence_Medium,
                    Backout => Backout_Slow,
                    Requires_Reboot => True,
                    Description => To_Unbounded_String
                      ("Windows Volume Shadow Copy"),
                    Warnings => To_Unbounded_String
                      ("VSS restore may require reboot"),
                    Estimated_Time => 180,
                    Applicable => True,
                    Reason => To_Unbounded_String
                      ("VSS provides Windows system restore points"));

         when None =>
            --  No snapshot support - fallback to transaction log
            Rec := (Primary => Strategy_Transaction_Log,
                    Primary_Confidence => Confidence_High,
                    Fallback => Strategy_Manual,
                    Fallback_Confidence => Confidence_Low,
                    Backout => Backout_Manual,
                    Requires_Reboot => False,
                    Description => To_Unbounded_String
                      ("Transaction log only (no filesystem snapshots)"),
                    Warnings => To_Unbounded_String
                      ("No automatic rollback; manual recovery may be needed"),
                    Estimated_Time => 0,  --  Unknown
                    Applicable => True,
                    Reason => To_Unbounded_String
                      ("No snapshot backend available; using transaction log"));
      end case;

      return Rec;
   end Lookup_Strategy;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Selection
   --  ═══════════════════════════════════════════════════════════════════════

   function Get_Strategy
     (Platform : Platform_Info;
      PM       : Package_Manager_Type;
      Risk     : Risk_Level) return Strategy_Recommendation
   is
      Has_Native : Boolean;
   begin
      --  Check if PM has native recovery
      Has_Native := Has_Native_Transactions (PM);

      return Lookup_Strategy
        (PM_Type    => PM,
         Has_Native => Has_Native,
         Snapshot   => Platform.Snapshot_Support,
         Risk       => Risk);
   end Get_Strategy;

   function Get_Strategy_For_Plugin
     (Meta : Plugin_Metadata;
      Risk : Risk_Level) return Strategy_Recommendation
   is
   begin
      return Lookup_Strategy
        (PM_Type    => Meta.PM_Type,
         Has_Native => Meta.Has_Native_Recovery,
         Snapshot   => Meta.Preferred_Snapshot,
         Risk       => Risk);
   end Get_Strategy_For_Plugin;

   function Get_Best_Recovery_Backend
     (Platform : Platform_Info) return Snapshot_Backend
   is
   begin
      --  Priority order: Native > Btrfs > ZFS > LVM > None
      if Platform.Primary_PM in Guix | Nix | RPM_OSTree then
         return Native;
      elsif Platform.Can_Use_Btrfs then
         return Btrfs;
      elsif Platform.Can_Use_ZFS then
         return ZFS;
      elsif Platform.Can_Use_LVM then
         return LVM;
      else
         return Platform.Snapshot_Support;
      end if;
   end Get_Best_Recovery_Backend;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Validation
   --  ═══════════════════════════════════════════════════════════════════════

   function Validate_Strategy
     (Strat    : Strategy_Recommendation;
      Platform : Platform_Info) return Boolean
   is
   begin
      case Strat.Primary is
         when Strategy_None =>
            return True;
         when Strategy_Native =>
            return Has_Native_Transactions (Platform.Primary_PM);
         when Strategy_Btrfs_Snapshot =>
            return Platform.Can_Use_Btrfs;
         when Strategy_ZFS_Snapshot =>
            return Platform.Can_Use_ZFS;
         when Strategy_LVM_Snapshot =>
            return Platform.Can_Use_LVM;
         when Strategy_Snapper =>
            return Platform.Can_Use_Btrfs or Platform.Can_Use_LVM;
         when Strategy_Ostree =>
            return Platform.Primary_PM = RPM_OSTree;
         when Strategy_APFS =>
            return Platform.OS = Darwin;
         when Strategy_VSS =>
            return Platform.OS = Windows;
         when Strategy_Transaction_Log | Strategy_Manual =>
            return True;  --  Always available
      end case;
   end Validate_Strategy;

   function Strategy_Meets_Risk
     (Strat : Strategy_Recommendation;
      Risk  : Risk_Level) return Boolean
   is
   begin
      --  For critical operations, we need reliable backout
      case Risk is
         when Risk_None =>
            return True;
         when Risk_Low =>
            return Strat.Backout /= Backout_None;
         when Risk_Medium =>
            return Strat.Backout in Backout_Instant | Backout_Fast | Backout_Slow;
         when Risk_High | Risk_Critical =>
            return Strat.Backout in Backout_Instant | Backout_Fast and
                   Strat.Primary_Confidence in Confidence_Proven | Confidence_High;
      end case;
   end Strategy_Meets_Risk;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Human-Readable Descriptions
   --  ═══════════════════════════════════════════════════════════════════════

   function Strategy_Name (S : Recovery_Strategy) return String is
   begin
      case S is
         when Strategy_None           => return "None";
         when Strategy_Native         => return "Native PM Recovery";
         when Strategy_Btrfs_Snapshot => return "Btrfs Snapshot";
         when Strategy_ZFS_Snapshot   => return "ZFS Snapshot";
         when Strategy_LVM_Snapshot   => return "LVM Snapshot";
         when Strategy_Snapper        => return "Snapper";
         when Strategy_Ostree         => return "rpm-ostree Deployment";
         when Strategy_APFS           => return "APFS Snapshot";
         when Strategy_VSS            => return "Volume Shadow Copy";
         when Strategy_Transaction_Log => return "Transaction Log";
         when Strategy_Manual         => return "Manual Recovery";
      end case;
   end Strategy_Name;

   function Risk_Name (R : Risk_Level) return String is
   begin
      case R is
         when Risk_None     => return "None";
         when Risk_Low      => return "Low";
         when Risk_Medium   => return "Medium";
         when Risk_High     => return "High";
         when Risk_Critical => return "Critical";
      end case;
   end Risk_Name;

   function Backout_Description (B : Backout_Capability) return String is
   begin
      case B is
         when Backout_Instant => return "Instant rollback (< 1 second)";
         when Backout_Fast    => return "Fast restore (< 1 minute)";
         when Backout_Slow    => return "Full restore (minutes)";
         when Backout_Reboot  => return "Requires system reboot";
         when Backout_Manual  => return "Manual intervention required";
         when Backout_None    => return "No rollback available";
      end case;
   end Backout_Description;

   function Confidence_Description (C : Strategy_Confidence) return String is
   begin
      case C is
         when Confidence_Proven  => return "Formally verified/extensively tested";
         when Confidence_High    => return "Well-tested, reliable";
         when Confidence_Medium  => return "Generally works, some edge cases";
         when Confidence_Low     => return "Experimental";
         when Confidence_Unknown => return "Not tested";
      end case;
   end Confidence_Description;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Strategy Execution
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Execute_Pre_Operation_Strategy
     (Strat   : Strategy_Recommendation;
      Desc    : String;
      Success : out Boolean;
      Point   : out Snapshot_ID)
   is
      Snap_Info : Reversibility_Types.Snapshot_Info;
   begin
      Success := False;
      Point := Null_Snapshot;

      case Strat.Primary is
         when Strategy_None =>
            --  No snapshot needed
            Success := True;
            Point := Null_Snapshot;

         when Strategy_Native | Strategy_Btrfs_Snapshot |
              Strategy_ZFS_Snapshot | Strategy_LVM_Snapshot |
              Strategy_Snapper | Strategy_Ostree | Strategy_APFS |
              Strategy_VSS | Strategy_Transaction_Log =>
            --  Create snapshot via Snapshot_Manager
            Snapshot_Manager.Create_Snapshot
              (Description => Desc,
               Kind        => Pre_Transaction,
               Snapshot    => Snap_Info,
               Success     => Success);
            if Success then
               Point := Snap_Info.ID;
            end if;

         when Strategy_Manual =>
            --  Log warning but proceed
            Success := True;
            Point := Null_Snapshot;
      end case;
   end Execute_Pre_Operation_Strategy;

   procedure Execute_Backout
     (Strat  : Strategy_Recommendation;
      Point  : Snapshot_ID;
      Result : out Rollback_Status)
   is
      Rollback_Result : Reversibility_Types.Rollback_Result;
   begin
      if Point = Null_Snapshot then
         Result := Not_Started;
         return;
      end if;

      Snapshot_Manager.Rollback_To_Snapshot (Point, Rollback_Result);
      Result := Rollback_Result.Status;
   end Execute_Backout;

end Strategy_Matrix;
