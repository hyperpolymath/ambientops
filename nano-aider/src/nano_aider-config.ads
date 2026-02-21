-------------------------------------------------------------------------------
--  nano-aider - Configuration File Management
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

package Nano_Aider.Config is

   --  Configuration file locations
   type Config_Location is
     (Loc_System,      -- /etc/nanorc
      Loc_User,        -- ~/.nanorc or ~/.config/nano/nanorc
      Loc_Local,       -- ./.nanorc (project-local)
      Loc_Custom);     -- User-specified path

   --  Load configuration
   procedure Load_Default;
   procedure Load_From_File (Path : String);
   procedure Load_System_Config;
   procedure Load_User_Config;

   --  Save configuration
   procedure Save_To_File (Path : String);
   procedure Save_User_Config;

   --  Export formats
   procedure Export_Nanorc (Path : String);
   procedure Export_Micro_Json (Path : String);
   procedure Export_Markdown (Path : String);

   --  Configuration queries
   function Get_Config_Path return String;
   function Is_Modified return Boolean;
   function Get_Nano_Version return String;

   --  Merge configurations
   procedure Merge_Config (Path : String);
   procedure Clear_Config;

end Nano_Aider.Config;
