--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

with Ada.Text_IO;
with Ada.Calendar;
with Ada.Calendar.Formatting;

package body TotalUpdate.Logging is

   use Ada.Text_IO;

   --  State
   Current_Level  : Log_Level := Info;
   Console_Enabled : Boolean := True;
   Log_File_Path  : String (1 .. 256) := (others => ' ');
   Log_File_Len   : Natural := 0;
   Log_File       : File_Type;
   File_Open      : Boolean := False;

   function Level_Name (Level : Log_Level) return String is
   begin
      case Level is
         when Debug    => return "DEBUG";
         when Info     => return "INFO ";
         when Warning  => return "WARN ";
         when Error    => return "ERROR";
         when Critical => return "CRIT ";
      end case;
   end Level_Name;

   function Timestamp return String is
   begin
      return Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   end Timestamp;

   procedure Initialize (Min_Level : Log_Level := Info) is
   begin
      Current_Level := Min_Level;
   end Initialize;

   procedure Shutdown is
   begin
      if File_Open then
         Close (Log_File);
         File_Open := False;
      end if;
   end Shutdown;

   procedure Log (Level : Log_Level; Message : String) is
      Line : constant String :=
        "[" & Timestamp & "] [" & Level_Name (Level) & "] " & Message;
   begin
      if Level >= Current_Level then
         --  Console output
         if Console_Enabled then
            if Level >= Warning then
               Put_Line (Standard_Error, Line);
            else
               Put_Line (Line);
            end if;
         end if;

         --  File output
         if File_Open then
            Put_Line (Log_File, Line);
            Flush (Log_File);
         end if;
      end if;
   end Log;

   procedure Debug (Message : String) is
   begin
      Log (Debug, Message);
   end Debug;

   procedure Info (Message : String) is
   begin
      Log (Info, Message);
   end Info;

   procedure Warning (Message : String) is
   begin
      Log (Warning, Message);
   end Warning;

   procedure Error (Message : String) is
   begin
      Log (Error, Message);
   end Error;

   procedure Critical (Message : String) is
   begin
      Log (Critical, Message);
   end Critical;

   procedure Set_Level (Level : Log_Level) is
   begin
      Current_Level := Level;
   end Set_Level;

   procedure Set_Console (Enabled : Boolean) is
   begin
      Console_Enabled := Enabled;
   end Set_Console;

   procedure Set_Log_File (Path : String) is
   begin
      --  Close existing file if open
      if File_Open then
         Close (Log_File);
         File_Open := False;
      end if;

      --  Open new file
      Log_File_Path (1 .. Path'Length) := Path;
      Log_File_Len := Path'Length;

      Create (Log_File, Append_File, Path);
      File_Open := True;

   exception
      when others =>
         Error ("Could not open log file: " & Path);
   end Set_Log_File;

end TotalUpdate.Logging;
