--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TotalUpdate.Watcher - File and package database watcher
--  Monitors package manager databases for external changes

package TotalUpdate.Watcher is

   --  Initialize watcher (detect available package managers)
   procedure Initialize;

   --  Process pending filesystem events (called from main loop)
   procedure Process;

   --  Shutdown watcher
   procedure Shutdown;

   --  Add a path to watch
   procedure Watch (Path : String);

   --  Remove a path from watch list
   procedure Unwatch (Path : String);

   --  Check if changes have been detected
   function Changes_Detected return Boolean;

   --  Clear the changes flag
   procedure Clear_Changes;

   --  Get number of watched paths
   function Watched_Path_Count return Natural;

end TotalUpdate.Watcher;
