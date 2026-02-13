--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  TUI Main Window - ncurses-based terminal interface for DNFinition

with Platform_Detection; use Platform_Detection;

package TUI.Main_Window is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Window Modes
   --  ═══════════════════════════════════════════════════════════════════════

   type View_Mode is
     (Package_Browser,    --  Browse/search packages (like aptitude)
      Installed_List,     --  View installed packages
      Upgradable_List,    --  View upgradable packages
      Transaction_View,   --  View pending transaction
      Snapshot_View,      --  View and manage snapshots
      Log_View,           --  View transaction history
      Help_View);         --  Help screen

   --  ═══════════════════════════════════════════════════════════════════════
   --  Key Bindings (vi-style)
   --  ═══════════════════════════════════════════════════════════════════════

   --  Navigation:
   --    j/Down    - Move down
   --    k/Up      - Move up
   --    h/Left    - Collapse/back
   --    l/Right   - Expand/enter
   --    g         - Go to top
   --    G         - Go to bottom
   --    /         - Search
   --    n         - Next match
   --    N         - Previous match

   --  Actions:
   --    +         - Mark for install
   --    -         - Mark for remove
   --    u         - Mark for upgrade
   --    U         - Upgrade all
   --    p         - Pin version
   --    Enter     - Apply transaction
   --    Backspace - Clear marks
   --    s         - Snapshot menu
   --    r         - Rollback menu

   --  Views:
   --    1         - Package browser
   --    2         - Installed packages
   --    3         - Upgradable packages
   --    4         - Transaction view
   --    5         - Snapshots
   --    6         - Logs

   --  Other:
   --    q         - Quit
   --    ?         - Help

   --  ═══════════════════════════════════════════════════════════════════════
   --  Main Interface
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Initialize (Platform : Platform_Info);
   --  Initialize ncurses and set up windows

   procedure Run (Platform : Platform_Info);
   --  Main event loop

   procedure Shutdown;
   --  Clean up ncurses

   --  ═══════════════════════════════════════════════════════════════════════
   --  View Management
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Switch_View (Mode : View_Mode);
   --  Switch to a different view

   function Current_View return View_Mode;
   --  Get current view mode

   procedure Refresh_View;
   --  Refresh current view

   --  ═══════════════════════════════════════════════════════════════════════
   --  Status Bar
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Set_Status (Message : String);
   --  Set status bar message

   procedure Clear_Status;
   --  Clear status bar

   procedure Show_Error (Message : String);
   --  Show error in status bar (red)

   procedure Show_Success (Message : String);
   --  Show success in status bar (green)

   --  ═══════════════════════════════════════════════════════════════════════
   --  Confirmation Dialogs
   --  ═══════════════════════════════════════════════════════════════════════

   function Confirm (Prompt : String) return Boolean;
   --  Yes/No confirmation dialog

   function Confirm_Transaction return Boolean;
   --  Confirm pending transaction with details

   function Confirm_Rollback (Snapshot_ID : Natural) return Boolean;
   --  Confirm rollback with snapshot details

end TUI.Main_Window;
