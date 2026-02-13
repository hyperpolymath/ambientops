--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TotalUpdate.Config - Configuration management
--  Loads and manages configuration from Scheme files

package TotalUpdate.Config is

   --  Load configuration from specified path
   procedure Load (Path : String);

   --  Load from default locations
   procedure Load_Default;

   --  Reload configuration (on SIGHUP)
   procedure Reload;

   --  Configuration getters
   function Get_Check_Interval return Duration;
   function Get_Auto_Update return Boolean;
   function Get_Snapshot_Method return String;
   function Get_Bandwidth_Limit return Natural;
   function Get_Max_Parallel_Downloads return Positive;
   function Is_Loaded return Boolean;

   --  Configuration setters (runtime override)
   procedure Set_Check_Interval (Interval : Duration);
   procedure Set_Auto_Update (Enabled : Boolean);

end TotalUpdate.Config;
