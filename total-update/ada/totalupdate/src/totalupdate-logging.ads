--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TotalUpdate.Logging - Logging subsystem
--  Logs to syslog and/or file with configurable verbosity

package TotalUpdate.Logging is

   type Log_Level is (Debug, Info, Warning, Error, Critical);

   --  Initialize logging subsystem
   procedure Initialize (Min_Level : Log_Level := Info);

   --  Shutdown logging
   procedure Shutdown;

   --  Log messages at various levels
   procedure Debug (Message : String);
   procedure Info (Message : String);
   procedure Warning (Message : String);
   procedure Error (Message : String);
   procedure Critical (Message : String);

   --  Generic log procedure
   procedure Log (Level : Log_Level; Message : String);

   --  Set minimum log level
   procedure Set_Level (Level : Log_Level);

   --  Enable/disable console output
   procedure Set_Console (Enabled : Boolean);

   --  Set log file path
   procedure Set_Log_File (Path : String);

end TotalUpdate.Logging;
