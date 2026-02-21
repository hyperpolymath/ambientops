-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Personal Sysadmin TUI - Main entry point
--
-- Provides an interactive terminal interface for:
-- - Querying the SLM for help with system issues
-- - Viewing system health and active rules
-- - Managing rule lifecycle
-- - Monitoring daemon status

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;      use Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Terminal_Interface.Curses; use Terminal_Interface.Curses;
with PSA_Client;
with PSA_UI;

procedure PSA_TUI is

   -- TUI state
   Current_View  : PSA_UI.View_Type := PSA_UI.Dashboard;
   Running       : Boolean := True;
   Refresh_Rate  : constant Duration := 1.0;

   -- Connection to PSA daemon
   Client        : PSA_Client.Connection;
   Connected     : Boolean := False;

   -- UI windows
   Main_Win      : Window;
   Status_Win    : Window;
   Input_Win     : Window;
   Help_Win      : Window;

begin
   -- Parse command line
   if Argument_Count > 0 then
      if Argument (1) = "--help" or Argument (1) = "-h" then
         Put_Line ("PSA TUI - Personal Sysadmin Terminal Interface");
         Put_Line ("");
         Put_Line ("Usage: psa-tui [OPTIONS]");
         Put_Line ("");
         Put_Line ("Options:");
         Put_Line ("  --help, -h     Show this help");
         Put_Line ("  --socket PATH  Connect to custom socket path");
         Put_Line ("");
         Put_Line ("Keys:");
         Put_Line ("  q          Quit");
         Put_Line ("  h          Show health dashboard");
         Put_Line ("  r          Show rules");
         Put_Line ("  a          Ask SLM a question");
         Put_Line ("  p          Show proposals");
         Put_Line ("  l          Show logs");
         Put_Line ("  ?          Show help");
         return;
      end if;
   end if;

   -- Initialize curses
   Init_Screen;
   Set_NL_Mode (False);
   Set_Echo_Mode (False);
   Set_Cbreak_Mode (True);
   Set_KeyPad_Mode (Standard_Window, True);

   -- Enable colors if supported
   if Has_Colors then
      Start_Color;
      Init_Pair (1, Color_White, Color_Blue);   -- Header
      Init_Pair (2, Color_Green, Color_Black);  -- Good/Success
      Init_Pair (3, Color_Yellow, Color_Black); -- Warning
      Init_Pair (4, Color_Red, Color_Black);    -- Error/Critical
      Init_Pair (5, Color_Cyan, Color_Black);   -- Info
   end if;

   -- Create windows
   declare
      Max_Y, Max_X : Line_Position;
   begin
      Get_Size (Standard_Window, Max_Y, Max_X);

      -- Status bar at top
      Status_Win := Create (1, Max_X, 0, 0);
      Set_Background (Status_Win, Color_Pair (1));

      -- Main content area
      Main_Win := Create (Max_Y - 4, Max_X, 1, 0);
      Box (Main_Win);

      -- Input area at bottom
      Input_Win := Create (2, Max_X, Max_Y - 3, 0);
      Box (Input_Win);

      -- Help overlay (hidden by default)
      Help_Win := Create (Max_Y - 6, Max_X - 10, 3, 5);
   end;

   -- Connect to PSA daemon
   begin
      PSA_Client.Connect (Client, "/run/user/" &
         Ada.Environment_Variables.Value ("UID", "1000") & "/psa.sock");
      Connected := True;
   exception
      when others =>
         Connected := False;
   end;

   -- Main event loop
   Main_Loop:
   while Running loop
      -- Update status bar
      PSA_UI.Draw_Status_Bar (Status_Win, Connected, Current_View);

      -- Draw current view
      case Current_View is
         when PSA_UI.Dashboard =>
            PSA_UI.Draw_Dashboard (Main_Win, Client, Connected);

         when PSA_UI.Rules =>
            PSA_UI.Draw_Rules (Main_Win, Client, Connected);

         when PSA_UI.Ask_SLM =>
            PSA_UI.Draw_Ask_Interface (Main_Win, Input_Win, Client, Connected);

         when PSA_UI.Proposals =>
            PSA_UI.Draw_Proposals (Main_Win, Client, Connected);

         when PSA_UI.Logs =>
            PSA_UI.Draw_Logs (Main_Win, Client, Connected);

         when PSA_UI.Help =>
            PSA_UI.Draw_Help (Help_Win);
      end case;

      -- Refresh all windows
      Refresh (Status_Win);
      Refresh (Main_Win);
      Refresh (Input_Win);

      -- Handle input with timeout (for auto-refresh)
      Set_Timeout_Mode (Standard_Window, Delayed, Integer (Refresh_Rate * 1000.0));

      declare
         Key : Key_Code;
      begin
         Key := Get_Keystroke;

         case Key is
            when Character'Pos ('q') | Character'Pos ('Q') =>
               Running := False;

            when Character'Pos ('h') | Character'Pos ('H') =>
               Current_View := PSA_UI.Dashboard;

            when Character'Pos ('r') | Character'Pos ('R') =>
               Current_View := PSA_UI.Rules;

            when Character'Pos ('a') | Character'Pos ('A') =>
               Current_View := PSA_UI.Ask_SLM;

            when Character'Pos ('p') | Character'Pos ('P') =>
               Current_View := PSA_UI.Proposals;

            when Character'Pos ('l') | Character'Pos ('L') =>
               Current_View := PSA_UI.Logs;

            when Character'Pos ('?') =>
               Current_View := PSA_UI.Help;

            when Key_Resize =>
               -- Handle terminal resize
               PSA_UI.Handle_Resize (Main_Win, Status_Win, Input_Win);

            when others =>
               -- Pass to current view handler
               PSA_UI.Handle_Key (Current_View, Key, Client);
         end case;

      exception
         when others =>
            null;  -- Timeout or error, just refresh
      end;
   end loop Main_Loop;

   -- Cleanup
   Delete (Main_Win);
   Delete (Status_Win);
   Delete (Input_Win);
   Delete (Help_Win);
   End_Windows;

   if Connected then
      PSA_Client.Disconnect (Client);
   end if;

end PSA_TUI;
