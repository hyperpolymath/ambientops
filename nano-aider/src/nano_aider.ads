-------------------------------------------------------------------------------
--  nano-aider - Ada TUI for nano/micro Editor Configuration
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------
--
--  nano-aider is a sophisticated Terminal User Interface (TUI) application
--  designed to expose, configure, and manage the extensive hidden options
--  available in the nano and micro text editors.
--
--  Key Features:
--  - Discovery of all nano/micro configuration options (including hidden)
--  - Interactive TUI for browsing and modifying settings
--  - Profile management for different editing workflows
--  - Export to nanorc/micro config format
--  - SPARK annotations for critical sections
--
-------------------------------------------------------------------------------

package Nano_Aider is

   pragma Pure;

   --  Application metadata
   App_Name    : constant String := "nano-aider";
   App_Version : constant String := "0.1.0";
   App_Author  : constant String := "Jonathan D.A. Jewell";
   App_License : constant String := "MIT OR AGPL-3.0-or-later";

   --  Supported editors
   type Editor_Type is (Nano, Micro);

   --  Configuration file extensions
   Nanorc_Extension : constant String := ".nanorc";
   Micro_Extension  : constant String := ".json";

end Nano_Aider;
