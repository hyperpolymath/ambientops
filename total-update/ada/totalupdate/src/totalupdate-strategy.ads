--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TotalUpdate.Strategy - Snapshot and recovery strategy management
--  Selects optimal snapshot method based on platform capabilities

package TotalUpdate.Strategy is

   type Snapshot_Backend is
     (None, Native, Btrfs, ZFS, LVM, Snapper, Transaction_Log);

   type Risk_Level is (Low, Medium, High, Critical);

   --  Initialize strategy engine (detect available backends)
   procedure Initialize;

   --  Shutdown strategy engine
   procedure Shutdown;

   --  Get current strategy name
   function Current_Strategy_Name return String;

   --  Get active snapshot backend
   function Active_Backend return Snapshot_Backend;

   --  Check if we have a valid recovery point
   function Has_Recovery_Point return Boolean;

   --  Create a recovery point before an operation
   procedure Create_Recovery_Point
     (Description : String;
      Success     : out Boolean);

   --  Rollback to the last recovery point
   procedure Rollback (Success : out Boolean);

   --  Check if strategy is adequate for risk level
   function Adequate_For_Risk (Risk : Risk_Level) return Boolean;

end TotalUpdate.Strategy;
