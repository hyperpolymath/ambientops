--  _pathroot TUI - Transaction Protocol Body
--  Handles command-line transaction protocol for scripting
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Pathroot_TUI.Core.Envbase;
with Pathroot_TUI.Core.Links;
with Pathroot_TUI.Core.Pathenv;

package body Pathroot_TUI.Core.Transactions is

   --  Command prefix
   Prefix : constant String := "PATHROOT:";

   ---------------------
   -- Output_Response --
   ---------------------

   procedure Output_Response
     (Status  : Response_Status;
      Command : String;
      Result  : String)
   is
      Status_Str : constant String :=
        (case Status is
           when Status_OK      => "ok",
           when Status_Error   => "error",
           when Status_Warning => "warning");
   begin
      Put_Line ("{");
      Put_Line ("  ""status"": """ & Status_Str & """,");
      Put_Line ("  ""command"": """ & Command & """,");
      Put_Line ("  ""result"": " & Result);
      Put_Line ("}");
   end Output_Response;

   ------------------------
   -- Parse_Command_Type --
   ------------------------

   function Parse_Command_Type (Command : String) return Command_Type is
      Upper_Cmd : String := Command;
   begin
      --  Convert to uppercase for comparison
      for I in Upper_Cmd'Range loop
         if Upper_Cmd (I) in 'a' .. 'z' then
            Upper_Cmd (I) := Character'Val
              (Character'Pos (Upper_Cmd (I)) - 32);
         end if;
      end loop;

      if Index (Upper_Cmd, "QUERY:ENV") > 0 then
         return Cmd_Query_Env;
      elsif Index (Upper_Cmd, "SET:PROFILE:") > 0 then
         return Cmd_Set_Profile;
      elsif Index (Upper_Cmd, "LINK:") > 0 then
         return Cmd_Create_Link;
      elsif Index (Upper_Cmd, "AUDIT:LINKS") > 0 then
         return Cmd_Audit_Links;
      elsif Index (Upper_Cmd, "PATH:ADD:") > 0 then
         return Cmd_Path_Add;
      elsif Index (Upper_Cmd, "PATH:REMOVE:") > 0 then
         return Cmd_Path_Remove;
      else
         return Cmd_Unknown;
      end if;
   end Parse_Command_Type;

   ---------------------
   -- Process_Command --
   ---------------------

   procedure Process_Command (Command : String; Devtools_Root : String) is
      use Pathroot_TUI.Core.Envbase;

      Cmd_Type : Command_Type;
   begin
      --  Check for PATHROOT: prefix
      if Command'Length < Prefix'Length or else
         Command (Command'First .. Command'First + Prefix'Length - 1) /= Prefix
      then
         Output_Response
           (Status_Error,
            "UNKNOWN",
            """Invalid command format. Expected PATHROOT:command""");
         return;
      end if;

      Cmd_Type := Parse_Command_Type (Command);

      case Cmd_Type is
         when Cmd_Query_Env =>
            declare
               Info : constant Environment_Info := Load_Environment (Devtools_Root);
            begin
               Output_Response
                 (Status_OK,
                  "QUERY:ENV",
                  "{" &
                  """env"": """ & To_String (Info.Env) & """, " &
                  """profile"": """ & To_String (Info.Profile) & """, " &
                  """platform"": """ & To_String (Info.Platform) & """" &
                  "}");
            end;

         when Cmd_Set_Profile =>
            --  Extract profile name after "SET:PROFILE:"
            declare
               Pattern : constant String := "SET:PROFILE:";
               Pos     : constant Natural := Index (Command, Pattern);
               Profile : constant String :=
                 Command (Pos + Pattern'Length .. Command'Last);
               Old_Info : constant Environment_Info := Load_Environment (Devtools_Root);
            begin
               Switch_Profile (Devtools_Root, Profile);
               Output_Response
                 (Status_OK,
                  "SET:PROFILE",
                  "{""previous"": """ & To_String (Old_Info.Profile) &
                  """, ""current"": """ & Profile & """}");
            end;

         when Cmd_Create_Link =>
            --  Extract link and target paths from command
            --  Format: PATHROOT:LINK:link_path:target_path
            declare
               use Pathroot_TUI.Core.Links;
               Pattern   : constant String := "LINK:";
               Pos       : constant Natural := Index (Command, Pattern);
               Params    : constant String :=
                 Command (Pos + Pattern'Length .. Command'Last);
               Sep_Pos   : constant Natural := Index (Params, ":");
               Error_Msg : Unbounded_String;
               Success   : Boolean;
            begin
               if Sep_Pos = 0 then
                  Output_Response
                    (Status_Error,
                     "LINK",
                     """Invalid format. Expected PATHROOT:LINK:link_path:target_path""");
               else
                  declare
                     Link_Path   : constant String := Params (Params'First .. Sep_Pos - 1);
                     Target_Path : constant String := Params (Sep_Pos + 1 .. Params'Last);
                  begin
                     Success := Create_Link (Link_Path, Target_Path, Error_Msg);
                     if Success then
                        Output_Response
                          (Status_OK,
                           "LINK",
                           "{""link"": """ & Link_Path &
                           """, ""target"": """ & Target_Path & """}");
                     else
                        Output_Response
                          (Status_Error,
                           "LINK",
                           """" & To_String (Error_Msg) & """");
                     end if;
                  end;
               end if;
            end;

         when Cmd_Audit_Links =>
            declare
               use Pathroot_TUI.Core.Links;
               Result : constant Audit_Result := Audit_Links (Devtools_Root);
            begin
               Output_Response
                 (Status_OK,
                  "AUDIT:LINKS",
                  Audit_To_JSON (Result));
            end;

         when Cmd_Path_Add =>
            --  Extract path entry from command
            --  Format: PATHROOT:PATH:ADD:path_entry
            declare
               use Pathroot_TUI.Core.Pathenv;
               Pattern    : constant String := "PATH:ADD:";
               Pos        : constant Natural := Index (Command, Pattern);
               Entry_Path : constant String :=
                 Command (Pos + Pattern'Length .. Command'Last);
               Result     : constant Path_Result := Add_To_Path (Entry_Path);
            begin
               if Result.Success then
                  Output_Response
                    (Status_OK,
                     "PATH:ADD",
                     Result_To_JSON (Result));
               else
                  Output_Response
                    (Status_Error,
                     "PATH:ADD",
                     Result_To_JSON (Result));
               end if;
            end;

         when Cmd_Path_Remove =>
            --  Extract path entry from command
            --  Format: PATHROOT:PATH:REMOVE:path_entry
            declare
               use Pathroot_TUI.Core.Pathenv;
               Pattern    : constant String := "PATH:REMOVE:";
               Pos        : constant Natural := Index (Command, Pattern);
               Entry_Path : constant String :=
                 Command (Pos + Pattern'Length .. Command'Last);
               Result     : constant Path_Result := Remove_From_Path (Entry_Path);
            begin
               if Result.Success then
                  Output_Response
                    (Status_OK,
                     "PATH:REMOVE",
                     Result_To_JSON (Result));
               else
                  Output_Response
                    (Status_Error,
                     "PATH:REMOVE",
                     Result_To_JSON (Result));
               end if;
            end;

         when Cmd_Unknown =>
            Output_Response
              (Status_Error,
               "UNKNOWN",
               """Unknown command: " & Command & """");
      end case;

   exception
      when others =>
         Output_Response
           (Status_Error,
            "ERROR",
            """Internal error processing command""");
   end Process_Command;

end Pathroot_TUI.Core.Transactions;
