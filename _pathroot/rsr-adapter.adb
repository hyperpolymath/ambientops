--  RSR Adapter - Repository Starter/Customization Tool
--  Provides interactive customization of repository templates
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;      use Ada.Strings.Fixed;
with Ada.Directories;        use Ada.Directories;
with Ada.Command_Line;

procedure RSR_Adapter is

   --  AI configuration choice
   type AI_Choice is (Claude, Copilot, None);

   --  File operation choice
   type File_Action is (Keep, Blank, Delete);

   --  Maximum input line length
   Max_Line : constant := 256;

   -----------------
   -- Get_Input --
   -----------------

   function Get_Input (Prompt : String) return Unbounded_String is
      Line : String (1 .. Max_Line);
      Last : Natural;
   begin
      Put (Prompt & " ");
      Flush;
      Get_Line (Line, Last);
      return To_Unbounded_String (Trim (Line (1 .. Last), Ada.Strings.Both));
   end Get_Input;

   ----------------------
   -- Get_Menu_Choice --
   ----------------------

   function Get_AI_Choice (Prompt : String) return AI_Choice is
      Line : String (1 .. Max_Line);
      Last : Natural;
   begin
      Put_Line (Prompt);
      Put_Line ("  1. Claude (Anthropic)");
      Put_Line ("  2. Copilot (GitHub)");
      Put_Line ("  3. None");
      Put ("Enter choice [1-3]: ");
      Flush;

      Get_Line (Line, Last);

      if Last >= 1 then
         case Line (1) is
            when '1' => return Claude;
            when '2' => return Copilot;
            when '3' => return None;
            when others => return None;
         end case;
      else
         return None;
      end if;
   end Get_AI_Choice;

   -------------------------
   -- Get_File_Action --
   -------------------------

   function Get_File_Action (File_Name : String) return File_Action is
      Line : String (1 .. Max_Line);
      Last : Natural;
   begin
      Put_Line ("What to do with " & File_Name & "?");
      Put_Line ("  1. Keep");
      Put_Line ("  2. Blank (empty file)");
      Put_Line ("  3. Delete");
      Put ("Enter choice [1-3]: ");
      Flush;

      Get_Line (Line, Last);

      if Last >= 1 then
         case Line (1) is
            when '1' => return Keep;
            when '2' => return Blank;
            when '3' => return Delete;
            when others => return Keep;
         end case;
      else
         return Keep;
      end if;
   end Get_File_Action;

   -------------------
   -- Update_README --
   -------------------

   procedure Update_README (Repo_Name : Unbounded_String;
                            Author    : Unbounded_String) is
      Readme_Path : constant String := "README.adoc";
      File        : File_Type;
      Content     : Unbounded_String := Null_Unbounded_String;
      Line        : String (1 .. 4096);
      Last        : Natural;
   begin
      --  Check if README exists
      if not Exists (Readme_Path) then
         --  Create a new README
         Create (File, Out_File, Readme_Path);
         Put_Line (File, "= " & To_String (Repo_Name));
         Put_Line (File, ":author: " & To_String (Author));
         Put_Line (File, "");
         Put_Line (File, "== Description");
         Put_Line (File, "");
         Put_Line (File, "TODO: Add project description here.");
         Close (File);
         Put_Line ("Created: " & Readme_Path);
         return;
      end if;

      --  Read existing README
      Open (File, In_File, Readme_Path);
      while not End_Of_File (File) loop
         Get_Line (File, Line, Last);

         --  Replace placeholder tokens
         declare
            Current_Line : Unbounded_String := To_Unbounded_String (Line (1 .. Last));
         begin
            --  Replace {{PROJECT_NAME}} with actual name
            if Index (To_String (Current_Line), "{{PROJECT_NAME}}") > 0 then
               Current_Line := To_Unbounded_String (
                 Replace_Slice (To_String (Current_Line),
                   Index (To_String (Current_Line), "{{PROJECT_NAME}}"),
                   Index (To_String (Current_Line), "{{PROJECT_NAME}}") + 15,
                   To_String (Repo_Name)));
            end if;

            --  Replace {{AUTHOR}} with actual author
            if Index (To_String (Current_Line), "{{AUTHOR}}") > 0 then
               Current_Line := To_Unbounded_String (
                 Replace_Slice (To_String (Current_Line),
                   Index (To_String (Current_Line), "{{AUTHOR}}"),
                   Index (To_String (Current_Line), "{{AUTHOR}}") + 9,
                   To_String (Author)));
            end if;

            Append (Content, Current_Line & ASCII.LF);
         end;
      end loop;
      Close (File);

      --  Write updated content
      Create (File, Out_File, Readme_Path);
      Put (File, To_String (Content));
      Close (File);

      Put_Line ("Updated: " & Readme_Path);
   exception
      when others =>
         Put_Line ("Warning: Could not update README");
   end Update_README;

   ----------------
   -- Blank_File --
   ----------------

   procedure Blank_File (File_Path : String) is
      File : File_Type;
   begin
      if Exists (File_Path) then
         --  Truncate file to empty
         Create (File, Out_File, File_Path);
         Close (File);
         Put_Line ("Blanked: " & File_Path);
      else
         Put_Line ("Skipped (not found): " & File_Path);
      end if;
   exception
      when others =>
         Put_Line ("Warning: Could not blank " & File_Path);
   end Blank_File;

   -----------------
   -- Delete_File --
   -----------------

   procedure Delete_File (File_Path : String) is
   begin
      if Exists (File_Path) then
         Ada.Directories.Delete_File (File_Path);
         Put_Line ("Deleted: " & File_Path);
      else
         Put_Line ("Skipped (not found): " & File_Path);
      end if;
   exception
      when others =>
         Put_Line ("Warning: Could not delete " & File_Path);
   end Delete_File;

   ----------------------------
   -- Configure_AI_Context --
   ----------------------------

   procedure Configure_AI_Context (Choice : AI_Choice) is
      Claude_Context : constant String := ".claude/CLAUDE.md";
      Copilot_Dir    : constant String := ".github/copilot";
      AI_Config      : constant String := ".rhodium/ai-context.json";
   begin
      case Choice is
         when Claude =>
            --  Keep Claude config, remove Copilot
            Put_Line ("Configured for Claude AI assistance");
            if Exists (Copilot_Dir) then
               Delete_File (Copilot_Dir & "/instructions.md");
            end if;

         when Copilot =>
            --  Keep Copilot config, blank Claude
            Put_Line ("Configured for Copilot AI assistance");
            if Exists (Claude_Context) then
               Blank_File (Claude_Context);
            end if;

         when None =>
            --  Remove all AI configurations
            Put_Line ("AI assistance disabled");
            if Exists (Claude_Context) then
               Blank_File (Claude_Context);
            end if;
            if Exists (AI_Config) then
               Blank_File (AI_Config);
            end if;
      end case;
   end Configure_AI_Context;

   --  Main procedure variables
   Repo_Name : Unbounded_String;
   Author    : Unbounded_String;
   AI_Tool   : AI_Choice;

begin
   Put_Line ("=== RSR Adapter - Repository Customization ===");
   Put_Line ("");

   --  Check for non-interactive mode
   if Ada.Command_Line.Argument_Count >= 2 then
      Repo_Name := To_Unbounded_String (Ada.Command_Line.Argument (1));
      Author := To_Unbounded_String (Ada.Command_Line.Argument (2));
      AI_Tool := None;

      if Ada.Command_Line.Argument_Count >= 3 then
         declare
            AI_Arg : constant String := Ada.Command_Line.Argument (3);
         begin
            if AI_Arg = "claude" then
               AI_Tool := Claude;
            elsif AI_Arg = "copilot" then
               AI_Tool := Copilot;
            else
               AI_Tool := None;
            end if;
         end;
      end if;
   else
      --  Interactive mode
      Repo_Name := Get_Input ("Project Name?");
      Author := Get_Input ("Author Name?");
      AI_Tool := Get_AI_Choice ("Select AI Target:");
   end if;

   --  Perform customization
   Put_Line ("");
   Put_Line ("Customizing repository...");

   --  Update README with project info
   Update_README (Repo_Name, Author);

   --  Configure AI context files
   Configure_AI_Context (AI_Tool);

   Put_Line ("");
   Put_Line ("Repository customization complete!");

exception
   when others =>
      Put_Line ("Error: Repository customization failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end RSR_Adapter;
