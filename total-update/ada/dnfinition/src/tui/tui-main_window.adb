--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

with Ada.Text_IO;

package body TUI.Main_Window is

   use Ada.Text_IO;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Internal State
   --  ═══════════════════════════════════════════════════════════════════════

   Current_Mode    : View_Mode := Package_Browser;
   Is_Initialized  : Boolean := False;
   Status_Message  : String (1 .. 256) := (others => ' ');
   Status_Length   : Natural := 0;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Main Interface (Stubs for now - ncurses integration needed)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Initialize (Platform : Platform_Detection.Platform_Info) is
      pragma Unreferenced (Platform);
   begin
      Put_Line ("TUI: Initializing ncurses interface...");
      Put_Line ("(TUI not yet implemented - ncurses bindings required)");
      Is_Initialized := True;
   end Initialize;

   procedure Run (Platform : Platform_Detection.Platform_Info) is
      pragma Unreferenced (Platform);
   begin
      if not Is_Initialized then
         Put_Line ("Error: TUI not initialized");
         return;
      end if;

      Put_Line ("TUI: Main event loop starting...");
      Put_Line ("(Interactive mode not yet available)");

      --  Placeholder main loop
      loop
         --  Would process ncurses events here
         --  For now, just exit
         exit;
      end loop;

      Put_Line ("TUI: Exiting.");
   end Run;

   procedure Shutdown is
   begin
      Put_Line ("TUI: Shutting down ncurses...");
      Is_Initialized := False;
   end Shutdown;

   --  ═══════════════════════════════════════════════════════════════════════
   --  View Management
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Switch_View (Mode : View_Mode) is
   begin
      Current_Mode := Mode;
      Put_Line ("TUI: Switched to " & View_Mode'Image (Mode));
   end Switch_View;

   function Current_View return View_Mode is
   begin
      return Current_Mode;
   end Current_View;

   procedure Refresh_View is
   begin
      Put_Line ("TUI: Refreshing " & View_Mode'Image (Current_Mode));
   end Refresh_View;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Status Bar
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Set_Status (Message : String) is
   begin
      if Message'Length <= 256 then
         Status_Message (1 .. Message'Length) := Message;
         Status_Length := Message'Length;
      else
         Status_Message := Message (Message'First .. Message'First + 255);
         Status_Length := 256;
      end if;
      Put_Line ("[Status] " & Status_Message (1 .. Status_Length));
   end Set_Status;

   procedure Clear_Status is
   begin
      Status_Length := 0;
   end Clear_Status;

   procedure Show_Error (Message : String) is
   begin
      Put_Line ("[ERROR] " & Message);
      Set_Status ("Error: " & Message);
   end Show_Error;

   procedure Show_Success (Message : String) is
   begin
      Put_Line ("[OK] " & Message);
      Set_Status (Message);
   end Show_Success;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Confirmation Dialogs
   --  ═══════════════════════════════════════════════════════════════════════

   function Confirm (Prompt : String) return Boolean is
      Response : String (1 .. 10);
      Last     : Natural;
   begin
      Put (Prompt & " [y/N]: ");
      Get_Line (Response, Last);

      if Last > 0 and then (Response (1) = 'y' or Response (1) = 'Y') then
         return True;
      else
         return False;
      end if;
   exception
      when others =>
         return False;
   end Confirm;

   function Confirm_Transaction return Boolean is
   begin
      Put_Line ("Pending Transaction:");
      Put_Line ("  (Transaction details would be shown here)");
      return Confirm ("Apply this transaction?");
   end Confirm_Transaction;

   function Confirm_Rollback (Snapshot_ID : Natural) return Boolean is
   begin
      Put_Line ("Rollback to snapshot " & Natural'Image (Snapshot_ID));
      Put_Line ("  (Snapshot details would be shown here)");
      return Confirm ("Proceed with rollback?");
   end Confirm_Rollback;

end TUI.Main_Window;
