-- SPDX-License-Identifier: AGPL-3.0-or-later
-- PSA UI Components - TUI drawing routines

with Terminal_Interface.Curses; use Terminal_Interface.Curses;
with PSA_Client;

package PSA_UI is

   -- Available views
   type View_Type is (Dashboard, Rules, Ask_SLM, Proposals, Logs, Help);

   -- Draw the status bar
   procedure Draw_Status_Bar
     (Win       : Window;
      Connected : Boolean;
      View      : View_Type);

   -- Draw the health dashboard
   procedure Draw_Dashboard
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean);

   -- Draw rules list
   procedure Draw_Rules
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean);

   -- Draw SLM query interface
   procedure Draw_Ask_Interface
     (Main_Win  : Window;
      Input_Win : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean);

   -- Draw proposals list
   procedure Draw_Proposals
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean);

   -- Draw logs view
   procedure Draw_Logs
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean);

   -- Draw help overlay
   procedure Draw_Help (Win : Window);

   -- Handle key press in current view
   procedure Handle_Key
     (View   : View_Type;
      Key    : Key_Code;
      Client : PSA_Client.Connection);

   -- Handle terminal resize
   procedure Handle_Resize
     (Main_Win   : in out Window;
      Status_Win : in out Window;
      Input_Win  : in out Window);

end PSA_UI;
