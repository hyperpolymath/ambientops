--  _pathroot TUI - Envbase Module Body
--  Handles _envbase JSON parsing and manipulation
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Fixed;

package body Pathroot_TUI.Core.Envbase is

   use Ada.Directories;
   use Ada.Text_IO;
   use Ada.Strings.Fixed;

   ------------------
   -- Envbase_Path --
   ------------------

   function Envbase_Path (Devtools_Root : String) return String is
   begin
      --  Handle both Windows and POSIX path separators
      if Devtools_Root'Length > 0 and then
         (Devtools_Root (Devtools_Root'Last) = '/' or else
          Devtools_Root (Devtools_Root'Last) = '\')
      then
         return Devtools_Root & "_envbase";
      else
         --  Use forward slash for POSIX compatibility
         return Devtools_Root & "/_envbase";
      end if;
   end Envbase_Path;

   --------------------
   -- Envbase_Exists --
   --------------------

   function Envbase_Exists (Devtools_Root : String) return Boolean is
   begin
      return Exists (Envbase_Path (Devtools_Root));
   end Envbase_Exists;

   ----------------------
   -- Extract_JSON_Value --
   ----------------------

   function Extract_JSON_Value (Content : String; Key : String) return String is
      Key_Pattern : constant String := """" & Key & """:";
      Key_Pos     : Natural;
      Start_Pos   : Natural;
      End_Pos     : Natural;
   begin
      Key_Pos := Index (Content, Key_Pattern);
      if Key_Pos = 0 then
         return "";
      end if;

      --  Find the opening quote of the value
      Start_Pos := Index (Content (Key_Pos + Key_Pattern'Length .. Content'Last), """");
      if Start_Pos = 0 then
         return "";
      end if;
      Start_Pos := Start_Pos + 1;

      --  Find the closing quote
      End_Pos := Index (Content (Start_Pos .. Content'Last), """");
      if End_Pos = 0 then
         return "";
      end if;

      return Content (Start_Pos .. End_Pos - 1);
   end Extract_JSON_Value;

   ----------------------
   -- Load_Environment --
   ----------------------

   function Load_Environment (Devtools_Root : String) return Environment_Info is
      Info : Environment_Info;
      Path : constant String := Envbase_Path (Devtools_Root);
      File : File_Type;
      Content : Unbounded_String := Null_Unbounded_String;
      Line : String (1 .. 1024);
      Last : Natural;
   begin
      if not Exists (Path) then
         return Info;
      end if;

      --  Read entire file
      Open (File, In_File, Path);
      while not End_Of_File (File) loop
         Get_Line (File, Line, Last);
         Append (Content, Line (1 .. Last));
      end loop;
      Close (File);

      --  Parse JSON (simple extraction for known keys)
      declare
         C : constant String := To_String (Content);
      begin
         Info.Env := To_Unbounded_String (Extract_JSON_Value (C, "env"));
         Info.Profile := To_Unbounded_String (Extract_JSON_Value (C, "profile"));
         Info.Platform := To_Unbounded_String (Extract_JSON_Value (C, "platform"));
         Info.Version := To_Unbounded_String (Extract_JSON_Value (C, "version"));
         Info.Created := To_Unbounded_String (Extract_JSON_Value (C, "created"));
         Info.Is_Valid := Length (Info.Env) > 0;
      end;

      return Info;
   exception
      when others =>
         return Info;
   end Load_Environment;

   ----------------------
   -- Save_Environment --
   ----------------------

   procedure Save_Environment
     (Devtools_Root : String;
      Info          : Environment_Info)
   is
      Path : constant String := Envbase_Path (Devtools_Root);
      File : File_Type;
   begin
      Create (File, Out_File, Path);
      Put_Line (File, "{");
      Put_Line (File, "  ""env"": """ & To_String (Info.Env) & """,");
      Put_Line (File, "  ""profile"": """ & To_String (Info.Profile) & """,");
      Put_Line (File, "  ""platform"": """ & To_String (Info.Platform) & """,");

      if Length (Info.Version) > 0 then
         Put_Line (File, "  ""version"": """ & To_String (Info.Version) & """,");
      end if;

      if Length (Info.Created) > 0 then
         Put_Line (File, "  ""created"": """ & To_String (Info.Created) & """");
      else
         Put_Line (File, "  ""created"": """"");
      end if;

      Put_Line (File, "}");
      Close (File);
   end Save_Environment;

   --------------------
   -- Switch_Profile --
   --------------------

   procedure Switch_Profile
     (Devtools_Root : String;
      Profile_Name  : String)
   is
      Info : Environment_Info := Load_Environment (Devtools_Root);
   begin
      Info.Profile := To_Unbounded_String (Profile_Name);
      Save_Environment (Devtools_Root, Info);
   end Switch_Profile;

end Pathroot_TUI.Core.Envbase;
