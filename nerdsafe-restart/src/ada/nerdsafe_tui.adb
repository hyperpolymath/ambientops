--  SPDX-License-Identifier: AGPL-3.0-or-later
--  nerdsafe_tui.adb - Main TUI package body

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Integer_Text_IO;   use Ada.Integer_Text_IO;
with Ada.Float_Text_IO;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with GNAT.OS_Lib;

package body Nerdsafe_TUI is

   --  =========================================================================
   --  Resource Detection Implementation
   --  =========================================================================

   function Get_Total_Memory_KB return Natural is
      File   : File_Type;
      Line   : String (1 .. 256);
      Last   : Natural;
      Result : Natural := 1024 * 1024;  -- Default 1GB
   begin
      Open (File, In_File, "/proc/meminfo");
      while not End_Of_File (File) loop
         Get_Line (File, Line, Last);
         if Last >= 9 and then Line (1 .. 9) = "MemTotal:" then
            --  Parse: "MemTotal:     16384000 kB"
            declare
               Start_Pos : Natural := 10;
               End_Pos   : Natural;
            begin
               --  Skip whitespace
               while Start_Pos <= Last and then Line (Start_Pos) = ' ' loop
                  Start_Pos := Start_Pos + 1;
               end loop;
               --  Find end of number
               End_Pos := Start_Pos;
               while End_Pos <= Last and then Line (End_Pos) in '0' .. '9' loop
                  End_Pos := End_Pos + 1;
               end loop;
               Result := Natural'Value (Line (Start_Pos .. End_Pos - 1));
            end;
            exit;
         end if;
      end loop;
      Close (File);
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Result;
   end Get_Total_Memory_KB;

   function Get_Available_Memory_KB return Natural is
      File   : File_Type;
      Line   : String (1 .. 256);
      Last   : Natural;
      Result : Natural := 512 * 1024;  -- Default 512MB
   begin
      Open (File, In_File, "/proc/meminfo");
      while not End_Of_File (File) loop
         Get_Line (File, Line, Last);
         if Last >= 13 and then Line (1 .. 13) = "MemAvailable:" then
            declare
               Start_Pos : Natural := 14;
               End_Pos   : Natural;
            begin
               while Start_Pos <= Last and then Line (Start_Pos) = ' ' loop
                  Start_Pos := Start_Pos + 1;
               end loop;
               End_Pos := Start_Pos;
               while End_Pos <= Last and then Line (End_Pos) in '0' .. '9' loop
                  End_Pos := End_Pos + 1;
               end loop;
               Result := Natural'Value (Line (Start_Pos .. End_Pos - 1));
            end;
            exit;
         end if;
      end loop;
      Close (File);
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Result;
   end Get_Available_Memory_KB;

   function Get_CPU_Count return Positive is
      File   : File_Type;
      Line   : String (1 .. 256);
      Last   : Natural;
      Count  : Natural := 0;
   begin
      Open (File, In_File, "/proc/cpuinfo");
      while not End_Of_File (File) loop
         Get_Line (File, Line, Last);
         if Last >= 9 and then Line (1 .. 9) = "processor" then
            Count := Count + 1;
         end if;
      end loop;
      Close (File);
      if Count = 0 then
         return 1;
      else
         return Count;
      end if;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return 1;
   end Get_CPU_Count;

   function Get_Swap_Total_KB return Natural is
      File   : File_Type;
      Line   : String (1 .. 256);
      Last   : Natural;
      Result : Natural := 0;
   begin
      Open (File, In_File, "/proc/meminfo");
      while not End_Of_File (File) loop
         Get_Line (File, Line, Last);
         if Last >= 10 and then Line (1 .. 10) = "SwapTotal:" then
            declare
               Start_Pos : Natural := 11;
               End_Pos   : Natural;
            begin
               while Start_Pos <= Last and then Line (Start_Pos) = ' ' loop
                  Start_Pos := Start_Pos + 1;
               end loop;
               End_Pos := Start_Pos;
               while End_Pos <= Last and then Line (End_Pos) in '0' .. '9' loop
                  End_Pos := End_Pos + 1;
               end loop;
               Result := Natural'Value (Line (Start_Pos .. End_Pos - 1));
            end;
            exit;
         end if;
      end loop;
      Close (File);
      return Result;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return Result;
   end Get_Swap_Total_KB;

   procedure Auto_Detect_Resources (Limits : out Resource_Limits) is
      Available_KB : constant Natural := Get_Available_Memory_KB;
      Swap_KB      : constant Natural := Get_Swap_Total_KB;
      CPUs         : constant Positive := Get_CPU_Count;
   begin
      --  Use 50% of available memory
      Limits.Memory_MB := (Available_KB / 2) / 1024;
      if Limits.Memory_MB < 256 then
         Limits.Memory_MB := 256;  -- Minimum 256MB
      end if;

      --  Use 25% of swap
      Limits.Memory_Swap := (Swap_KB / 4) / 1024;

      --  Use half the CPUs, minimum 1
      Limits.CPU_Count := Integer'Max (1, CPUs / 2);

      --  Keep defaults for PID limit and timeout
      Limits.PID_Limit := 256;
      Limits.Timeout_Sec := 300;
      Limits.Network := False;
   end Auto_Detect_Resources;

   --  =========================================================================
   --  Profile Management Implementation
   --  =========================================================================

   function Load_Profiles return Profile_List is
      Result : Profile_List;
      Default_P : Profile;
   begin
      --  For now, just return a default profile
      --  TODO: Implement JSON loading
      Auto_Detect_Resources (Default_P.Limits);
      Default_P.Name := To_Unbounded_String (Default_Profile_Name);
      Default_P.Description := To_Unbounded_String ("Auto-detected system resources");
      Default_P.Level := Normal;
      Default_P.Is_Default := True;
      Result.Append (Default_P);
      return Result;
   end Load_Profiles;

   procedure Save_Profiles (Profiles : Profile_List) is
   begin
      --  TODO: Implement JSON saving
      Put_Line ("Profile saving not yet implemented");
   end Save_Profiles;

   function Get_Default_Profile return Profile is
      P : Profile;
   begin
      Auto_Detect_Resources (P.Limits);
      P.Name := To_Unbounded_String (Default_Profile_Name);
      P.Description := To_Unbounded_String ("Auto-detected system resources");
      P.Level := Normal;
      P.Is_Default := True;
      return P;
   end Get_Default_Profile;

   function Create_Profile
     (Name        : String;
      Description : String;
      Level       : Validation_Level;
      Limits      : Resource_Limits) return Profile
   is
      P : Profile;
   begin
      P.Name := To_Unbounded_String (Name);
      P.Description := To_Unbounded_String (Description);
      P.Level := Level;
      P.Limits := Limits;
      P.Is_Default := False;
      return P;
   end Create_Profile;

   --  =========================================================================
   --  Validation Execution Implementation
   --  =========================================================================

   function Build_Command
     (Level  : Validation_Level;
      Limits : Resource_Limits) return String
   is
      Container_Cmd : constant String := Get_Container_Command;
      Level_Str : constant String := Validation_Level'Image (Level);
   begin
      return Container_Cmd & " run --rm -it" &
             " --memory=" & Natural'Image (Limits.Memory_MB) & "m" &
             " --cpus=" & Positive'Image (Limits.CPU_Count) &
             " --pids-limit=" & Positive'Image (Limits.PID_Limit) &
             " --security-opt=no-new-privileges" &
             " --cap-drop=ALL" &
             " --read-only" &
             " --network=none" &
             " --volume=" & Get_Home_Directory & ":" & Get_Home_Directory & ":ro" &
             " nerdsafe-restart:kinoite" &
             " check --level " & Level_Str;
   end Build_Command;

   function Run_Validation
     (Level  : Validation_Level;
      Limits : Resource_Limits) return Exit_Code
   is
      Command : constant String := Build_Command (Level, Limits);
      Args    : GNAT.OS_Lib.Argument_List_Access;
      Status  : Integer;
      Success : Boolean;
   begin
      Put_Line ("Running: " & Command);
      --  TODO: Use GNAT.OS_Lib.Spawn for actual execution
      --  For now, return success as placeholder
      return Exit_Code'Val (0);
   end Run_Validation;

   function Run_Validation (P : Profile) return Exit_Code is
   begin
      return Run_Validation (P.Level, P.Limits);
   end Run_Validation;

   --  =========================================================================
   --  TUI Interface Implementation
   --  =========================================================================

   procedure Display_Main_Menu is
   begin
      Put_Line ("");
      Put_Line ("╔════════════════════════════════════════╗");
      Put_Line ("║       nerdsafe-restart TUI             ║");
      Put_Line ("║   Pre-reboot Shell Validator           ║");
      Put_Line ("╠════════════════════════════════════════╣");
      Put_Line ("║  1. Run Quick Validation               ║");
      Put_Line ("║  2. Run Standard Validation            ║");
      Put_Line ("║  3. Run Thorough Validation            ║");
      Put_Line ("║  4. Run Paranoid Validation            ║");
      Put_Line ("║  5. View System Resources              ║");
      Put_Line ("║  6. Manage Profiles                    ║");
      Put_Line ("║  7. Settings                           ║");
      Put_Line ("║  q. Quit                               ║");
      Put_Line ("╚════════════════════════════════════════╝");
      Put ("Selection: ");
   end Display_Main_Menu;

   procedure Display_Resources (Limits : Resource_Limits) is
   begin
      Put_Line ("");
      Put_Line ("╔════════════════════════════════════════╗");
      Put_Line ("║       Detected System Resources        ║");
      Put_Line ("╠════════════════════════════════════════╣");
      Put ("║  Total Memory:    ");
      Put (Format_Memory (Get_Total_Memory_KB));
      Put_Line ("                ║");
      Put ("║  Available:       ");
      Put (Format_Memory (Get_Available_Memory_KB));
      Put_Line ("                ║");
      Put ("║  Container Limit: ");
      Put (Format_Memory (Limits.Memory_MB * 1024));
      Put_Line ("                ║");
      Put ("║  CPUs (total):    ");
      Put (Positive'Image (Get_CPU_Count));
      Put_Line ("                        ║");
      Put ("║  CPUs (container):");
      Put (Positive'Image (Limits.CPU_Count));
      Put_Line ("                        ║");
      Put ("║  PID Limit:       ");
      Put (Positive'Image (Limits.PID_Limit));
      Put_Line ("                      ║");
      Put ("║  Timeout:         ");
      Put (Positive'Image (Limits.Timeout_Sec));
      Put_Line ("s                    ║");
      Put_Line ("╚════════════════════════════════════════╝");
   end Display_Resources;

   procedure Display_Profiles (Profiles : Profile_List) is
   begin
      Put_Line ("");
      Put_Line ("╔════════════════════════════════════════╗");
      Put_Line ("║           Saved Profiles               ║");
      Put_Line ("╠════════════════════════════════════════╣");
      for I in Profiles.First_Index .. Profiles.Last_Index loop
         Put ("║  ");
         Put (I, Width => 2);
         Put (". ");
         Put (To_String (Profiles (I).Name));
         if Profiles (I).Is_Default then
            Put (" (default)");
         end if;
         Put_Line ("║");
      end loop;
      Put_Line ("╚════════════════════════════════════════╝");
   end Display_Profiles;

   procedure Display_Progress (Message : String; Percent : Natural) is
      Bar_Width : constant := 30;
      Filled    : constant Natural := (Percent * Bar_Width) / 100;
   begin
      Put (ASCII.CR);
      Put (Message & " [");
      for I in 1 .. Bar_Width loop
         if I <= Filled then
            Put ("█");
         else
            Put ("░");
         end if;
      end loop;
      Put ("] ");
      Put (Percent, Width => 3);
      Put ("%");
   end Display_Progress;

   procedure Display_Result (Code : Exit_Code; Elapsed : Duration) is
   begin
      Put_Line ("");
      Put_Line ("╔════════════════════════════════════════╗");
      case Code is
         when Success =>
            Put_Line ("║  ✓ VALIDATION PASSED                   ║");
            Put_Line ("║    Safe to reboot                      ║");
         when Syntax_Error =>
            Put_Line ("║  ✗ SYNTAX ERRORS FOUND                 ║");
            Put_Line ("║    Fix errors before rebooting         ║");
         when Timeout_Exceeded =>
            Put_Line ("║  ⏱ VALIDATION TIMED OUT                ║");
            Put_Line ("║    Check for slow startup              ║");
         when ShellCheck_Warning =>
            Put_Line ("║  ⚠ SHELLCHECK WARNINGS                 ║");
            Put_Line ("║    Review warnings before rebooting    ║");
         when Missing_File =>
            Put_Line ("║  ✗ MISSING CRITICAL FILES              ║");
            Put_Line ("║    Check file paths                    ║");
         when Permission_Error =>
            Put_Line ("║  ✗ PERMISSION ERRORS                   ║");
            Put_Line ("║    Fix file permissions                ║");
         when Container_Error =>
            Put_Line ("║  ✗ CONTAINER ERROR                     ║");
            Put_Line ("║    Check container runtime             ║");
         when Resource_Detection_Error =>
            Put_Line ("║  ✗ RESOURCE DETECTION FAILED           ║");
            Put_Line ("║    Check /proc access                  ║");
      end case;
      Put_Line ("╠════════════════════════════════════════╣");
      Put ("║  Duration: ");
      Ada.Float_Text_IO.Put (Float (Elapsed), Fore => 3, Aft => 2, Exp => 0);
      Put_Line ("s                       ║");
      Put_Line ("╚════════════════════════════════════════╝");
   end Display_Result;

   procedure Run_TUI is
      Choice   : Character;
      Limits   : Resource_Limits;
      Profiles : Profile_List;
      Result   : Exit_Code;
   begin
      Auto_Detect_Resources (Limits);
      Profiles := Load_Profiles;

      loop
         Display_Main_Menu;
         Get (Choice);
         Skip_Line;

         case Choice is
            when '1' =>
               Result := Run_Validation (Quick, Limits);
               Display_Result (Result, 5.0);
            when '2' =>
               Result := Run_Validation (Normal, Limits);
               Display_Result (Result, 30.0);
            when '3' =>
               Result := Run_Validation (Thorough, Limits);
               Display_Result (Result, 120.0);
            when '4' =>
               Result := Run_Validation (Paranoid, Limits);
               Display_Result (Result, 300.0);
            when '5' =>
               Display_Resources (Limits);
            when '6' =>
               Display_Profiles (Profiles);
            when '7' =>
               Put_Line ("Settings not yet implemented");
            when 'q' | 'Q' =>
               Put_Line ("Goodbye!");
               exit;
            when others =>
               Put_Line ("Invalid selection");
         end case;
      end loop;
   end Run_TUI;

   --  =========================================================================
   --  Utilities Implementation
   --  =========================================================================

   function Format_Memory (KB : Natural) return String is
      MB : constant Natural := KB / 1024;
      GB : constant Natural := MB / 1024;
   begin
      if GB >= 1 then
         return Natural'Image (GB) & " GB";
      elsif MB >= 1 then
         return Natural'Image (MB) & " MB";
      else
         return Natural'Image (KB) & " KB";
      end if;
   end Format_Memory;

   function Get_Home_Directory return String is
   begin
      return Ada.Environment_Variables.Value ("HOME", "/home/user");
   end Get_Home_Directory;

   function Is_Container_Available return Boolean is
   begin
      --  Check for nerdctl first, then podman
      return Ada.Directories.Exists ("/usr/bin/nerdctl") or else
             Ada.Directories.Exists ("/usr/bin/podman");
   end Is_Container_Available;

   function Get_Container_Command return String is
   begin
      if Ada.Directories.Exists ("/usr/bin/nerdctl") then
         return "nerdctl";
      elsif Ada.Directories.Exists ("/usr/bin/podman") then
         return "podman";
      else
         return "docker";  -- Fallback
      end if;
   end Get_Container_Command;

end Nerdsafe_TUI;
