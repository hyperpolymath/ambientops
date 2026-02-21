-- SPDX-License-Identifier: AGPL-3.0-or-later
-- PSA UI Components - Implementation

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Calendar;          use Ada.Calendar;
with Ada.Calendar.Formatting;

package body PSA_UI is

   -- Color pairs
   Header_Color  : constant Color_Pair := Color_Pair (1);
   Good_Color    : constant Color_Pair := Color_Pair (2);
   Warning_Color : constant Color_Pair := Color_Pair (3);
   Error_Color   : constant Color_Pair := Color_Pair (4);
   Info_Color    : constant Color_Pair := Color_Pair (5);

   procedure Draw_Status_Bar
     (Win       : Window;
      Connected : Boolean;
      View      : View_Type)
   is
      Max_X    : Column_Position;
      Max_Y    : Line_Position;
      View_Str : constant String := View_Type'Image (View);
      Time_Str : constant String := Ada.Calendar.Formatting.Image (Clock);
   begin
      Get_Size (Win, Max_Y, Max_X);
      Erase (Win);
      Set_Background (Win, Header_Color);

      -- Left: Connection status
      Move_Cursor (Win, 0, 1);
      if Connected then
         Set_Color (Win, Good_Color);
         Add (Win, "● Connected");
      else
         Set_Color (Win, Error_Color);
         Add (Win, "○ Disconnected");
      end if;

      -- Center: Current view
      Move_Cursor (Win, 0, Max_X / 2 - Column_Position (View_Str'Length / 2));
      Set_Color (Win, Header_Color);
      Add (Win, "[ " & View_Str & " ]");

      -- Right: Time
      Move_Cursor (Win, 0, Max_X - Column_Position (Time_Str'Length) - 1);
      Add (Win, Time_Str);

   end Draw_Status_Bar;

   procedure Draw_Dashboard
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean)
   is
      Max_X : Column_Position;
      Max_Y : Line_Position;
      Row   : Line_Position := 2;
   begin
      Get_Size (Win, Max_Y, Max_X);
      Erase (Win);
      Box (Win);

      -- Title
      Move_Cursor (Win, 1, 2);
      Set_Character_Attributes (Win, (Bold_Character => True, others => False));
      Add (Win, "System Health Dashboard");
      Set_Character_Attributes (Win, Normal_Video);

      if not Connected then
         Move_Cursor (Win, 3, 2);
         Set_Color (Win, Warning_Color);
         Add (Win, "Not connected to PSA daemon");
         Add (Win, " - Run: psa daemon");
         return;
      end if;

      -- Get health report
      declare
         Health : constant PSA_Client.Health_Report := PSA_Client.Get_Health (Client);
      begin
         -- Overall status
         Row := 3;
         Move_Cursor (Win, Row, 2);
         Add (Win, "Overall: ");

         case Health.Overall is
            when PSA_Client.Good =>
               Set_Color (Win, Good_Color);
               Add (Win, "HEALTHY ✓");
            when PSA_Client.Warning =>
               Set_Color (Win, Warning_Color);
               Add (Win, "WARNINGS !");
            when PSA_Client.Critical =>
               Set_Color (Win, Error_Color);
               Add (Win, "CRITICAL ✗");
         end case;

         -- Issues list
         Row := 5;
         Move_Cursor (Win, Row, 2);
         Set_Character_Attributes (Win, (Underline => True, others => False));
         Add (Win, "Issues:");
         Set_Character_Attributes (Win, Normal_Video);

         if Health.Issues /= null then
            for I in Health.Issues'Range loop
               Row := Row + 1;
               Move_Cursor (Win, Row, 4);

               case Health.Issues (I).Severity is
                  when PSA_Client.Critical =>
                     Set_Color (Win, Error_Color);
                     Add (Win, "✗ ");
                  when PSA_Client.Warning =>
                     Set_Color (Win, Warning_Color);
                     Add (Win, "! ");
                  when PSA_Client.Good =>
                     Set_Color (Win, Good_Color);
                     Add (Win, "✓ ");
               end case;

               Add (Win, To_String (Health.Issues (I).Message));

               exit when Row > Max_Y - 4;
            end loop;
         else
            Row := Row + 1;
            Move_Cursor (Win, Row, 4);
            Set_Color (Win, Good_Color);
            Add (Win, "No issues detected");
         end if;
      end;

      -- Help hint
      Move_Cursor (Win, Max_Y - 2, 2);
      Set_Color (Win, Info_Color);
      Add (Win, "Press ? for help | q to quit");

   exception
      when others =>
         Move_Cursor (Win, 3, 2);
         Set_Color (Win, Error_Color);
         Add (Win, "Error fetching health data");
   end Draw_Dashboard;

   procedure Draw_Rules
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean)
   is
      Max_X : Column_Position;
      Max_Y : Line_Position;
      Row   : Line_Position := 2;
   begin
      Get_Size (Win, Max_Y, Max_X);
      Erase (Win);
      Box (Win);

      Move_Cursor (Win, 1, 2);
      Set_Character_Attributes (Win, (Bold_Character => True, others => False));
      Add (Win, "Active Rules");
      Set_Character_Attributes (Win, Normal_Video);

      if not Connected then
         Move_Cursor (Win, 3, 2);
         Set_Color (Win, Warning_Color);
         Add (Win, "Not connected to PSA daemon");
         return;
      end if;

      -- Header
      Row := 3;
      Move_Cursor (Win, Row, 2);
      Set_Character_Attributes (Win, (Underline => True, others => False));
      Add (Win, "ID                    Name                          Success Rate");
      Set_Character_Attributes (Win, Normal_Video);

      -- Get rules
      declare
         Rules : constant PSA_Client.Rule_Summary_Array_Access :=
            PSA_Client.List_Rules (Client);
      begin
         if Rules /= null then
            for I in Rules'Range loop
               Row := Row + 1;
               Move_Cursor (Win, Row, 2);

               -- ID
               Add (Win, To_String (Rules (I).ID) (1 .. Integer'Min (20, Length (Rules (I).ID))));
               Move_Cursor (Win, Row, 24);

               -- Name
               Add (Win, To_String (Rules (I).Name) (1 .. Integer'Min (30, Length (Rules (I).Name))));
               Move_Cursor (Win, Row, 56);

               -- Success rate with color
               if Rules (I).Success_Rate >= 0.9 then
                  Set_Color (Win, Good_Color);
               elsif Rules (I).Success_Rate >= 0.7 then
                  Set_Color (Win, Warning_Color);
               else
                  Set_Color (Win, Error_Color);
               end if;

               Add (Win, Float'Image (Rules (I).Success_Rate * 100.0) (1 .. 5) & "%");

               exit when Row > Max_Y - 4;
            end loop;
         else
            Row := Row + 1;
            Move_Cursor (Win, Row, 2);
            Add (Win, "No rules loaded");
         end if;
      end;

   exception
      when others =>
         Move_Cursor (Win, 3, 2);
         Set_Color (Win, Error_Color);
         Add (Win, "Error fetching rules");
   end Draw_Rules;

   procedure Draw_Ask_Interface
     (Main_Win  : Window;
      Input_Win : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean)
   is
      Max_X : Column_Position;
      Max_Y : Line_Position;
   begin
      Get_Size (Main_Win, Max_Y, Max_X);
      Erase (Main_Win);
      Box (Main_Win);

      Move_Cursor (Main_Win, 1, 2);
      Set_Character_Attributes (Main_Win, (Bold_Character => True, others => False));
      Add (Main_Win, "Ask the SLM");
      Set_Character_Attributes (Main_Win, Normal_Video);

      Move_Cursor (Main_Win, 3, 2);
      Add (Main_Win, "Describe your problem and press Enter to query.");
      Move_Cursor (Main_Win, 4, 2);
      Add (Main_Win, "The system will check rules first, then consult the SLM.");

      -- Input prompt
      Erase (Input_Win);
      Box (Input_Win);
      Move_Cursor (Input_Win, 0, 2);
      Add (Input_Win, " Query ");
      Move_Cursor (Input_Win, 1, 2);
      Add (Input_Win, "> ");

   end Draw_Ask_Interface;

   procedure Draw_Proposals
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean)
   is
      Max_X : Column_Position;
      Max_Y : Line_Position;
   begin
      Get_Size (Win, Max_Y, Max_X);
      Erase (Win);
      Box (Win);

      Move_Cursor (Win, 1, 2);
      Set_Character_Attributes (Win, (Bold_Character => True, others => False));
      Add (Win, "Rule Proposals");
      Set_Character_Attributes (Win, Normal_Video);

      Move_Cursor (Win, 3, 2);
      Add (Win, "Proposals are solutions being evaluated for crystallization.");

      if not Connected then
         Move_Cursor (Win, 5, 2);
         Set_Color (Win, Warning_Color);
         Add (Win, "Not connected");
         return;
      end if;

      -- Would show pending proposals here

   end Draw_Proposals;

   procedure Draw_Logs
     (Win       : Window;
      Client    : PSA_Client.Connection;
      Connected : Boolean)
   is
      Max_X : Column_Position;
      Max_Y : Line_Position;
   begin
      Get_Size (Win, Max_Y, Max_X);
      Erase (Win);
      Box (Win);

      Move_Cursor (Win, 1, 2);
      Set_Character_Attributes (Win, (Bold_Character => True, others => False));
      Add (Win, "Activity Logs");
      Set_Character_Attributes (Win, Normal_Video);

      -- Would show scrollable log output here

   end Draw_Logs;

   procedure Draw_Help (Win : Window) is
      Max_X : Column_Position;
      Max_Y : Line_Position;
      Row   : Line_Position := 2;
   begin
      Get_Size (Win, Max_Y, Max_X);
      Erase (Win);
      Box (Win);

      Move_Cursor (Win, 1, 2);
      Set_Character_Attributes (Win, (Bold_Character => True, others => False));
      Add (Win, "Help - Keyboard Shortcuts");
      Set_Character_Attributes (Win, Normal_Video);

      Move_Cursor (Win, 3, 2);
      Add (Win, "h  - Health Dashboard");
      Move_Cursor (Win, 4, 2);
      Add (Win, "r  - Rules List");
      Move_Cursor (Win, 5, 2);
      Add (Win, "a  - Ask SLM");
      Move_Cursor (Win, 6, 2);
      Add (Win, "p  - Proposals");
      Move_Cursor (Win, 7, 2);
      Add (Win, "l  - Logs");
      Move_Cursor (Win, 8, 2);
      Add (Win, "?  - This Help");
      Move_Cursor (Win, 9, 2);
      Add (Win, "q  - Quit");

      Move_Cursor (Win, Max_Y - 2, 2);
      Set_Color (Win, Info_Color);
      Add (Win, "Press any key to close");

   end Draw_Help;

   procedure Handle_Key
     (View   : View_Type;
      Key    : Key_Code;
      Client : PSA_Client.Connection)
   is
   begin
      -- View-specific key handling would go here
      null;
   end Handle_Key;

   procedure Handle_Resize
     (Main_Win   : in out Window;
      Status_Win : in Out Window;
      Input_Win  : in out Window)
   is
      Max_Y, Max_X : Line_Position;
   begin
      Get_Size (Standard_Window, Max_Y, Max_X);

      -- Recreate windows with new sizes
      Delete (Status_Win);
      Delete (Main_Win);
      Delete (Input_Win);

      Status_Win := Create (1, Column_Position (Max_X), 0, 0);
      Main_Win := Create (Max_Y - 4, Column_Position (Max_X), 1, 0);
      Input_Win := Create (2, Column_Position (Max_X), Max_Y - 3, 0);

   end Handle_Resize;

end PSA_UI;
