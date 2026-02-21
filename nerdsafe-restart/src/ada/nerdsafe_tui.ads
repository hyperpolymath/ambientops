--  SPDX-License-Identifier: AGPL-3.0-or-later
--  nerdsafe_tui.ads - Main TUI package specification
--
--  This package provides the terminal user interface for nerdsafe-restart,
--  allowing users to configure validation settings, manage profiles, and
--  run validations interactively.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;

package Nerdsafe_TUI is

   --  =========================================================================
   --  Types
   --  =========================================================================

   --   Validation levels matching the shell script
   type Validation_Level is (Quick, Normal, Thorough, Paranoid);

   --   System resource limits
   type Resource_Limits is record
      Memory_MB    : Positive := 1024;
      Memory_Swap  : Natural := 0;
      CPU_Count    : Positive := 1;
      PID_Limit    : Positive := 256;
      Timeout_Sec  : Positive := 300;
      Network      : Boolean := False;  -- Always false for validation
   end record;

   --   Profile for saved configurations
   type Profile is record
      Name        : Unbounded_String;
      Description : Unbounded_String;
      Level       : Validation_Level := Normal;
      Limits      : Resource_Limits;
      Is_Default  : Boolean := False;
   end record;

   --   Exit codes matching the shell script
   type Exit_Code is
     (Success,
      Syntax_Error,
      Timeout_Exceeded,
      ShellCheck_Warning,
      Missing_File,
      Permission_Error,
      Container_Error,
      Resource_Detection_Error);

   for Exit_Code use
     (Success                   => 0,
      Syntax_Error              => 1,
      Timeout_Exceeded          => 2,
      ShellCheck_Warning        => 3,
      Missing_File              => 4,
      Permission_Error          => 5,
      Container_Error           => 10,
      Resource_Detection_Error  => 11);

   --  =========================================================================
   --  Resource Detection
   --  =========================================================================

   --   Detect system resources from /proc
   procedure Auto_Detect_Resources (Limits : out Resource_Limits);

   --   Get individual resource values
   function Get_Total_Memory_KB return Natural;
   function Get_Available_Memory_KB return Natural;
   function Get_CPU_Count return Positive;
   function Get_Swap_Total_KB return Natural;

   --  =========================================================================
   --  Profile Management
   --  =========================================================================

   package Profile_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Profile);

   subtype Profile_List is Profile_Vectors.Vector;

   --   Load profiles from config file
   function Load_Profiles return Profile_List;

   --   Save profiles to config file
   procedure Save_Profiles (Profiles : Profile_List);

   --   Get the default profile
   function Get_Default_Profile return Profile;

   --   Create a new profile
   function Create_Profile
     (Name        : String;
      Description : String;
      Level       : Validation_Level;
      Limits      : Resource_Limits) return Profile;

   --  =========================================================================
   --  Validation Execution
   --  =========================================================================

   --   Run validation with specified parameters
   function Run_Validation
     (Level  : Validation_Level;
      Limits : Resource_Limits) return Exit_Code;

   --   Run validation using a profile
   function Run_Validation (P : Profile) return Exit_Code;

   --   Build the nerdctl command for validation
   function Build_Command
     (Level  : Validation_Level;
      Limits : Resource_Limits) return String;

   --  =========================================================================
   --  TUI Interface
   --  =========================================================================

   --   Main TUI entry point
   procedure Run_TUI;

   --   Display main menu and get selection
   procedure Display_Main_Menu;

   --   Display resource detection screen
   procedure Display_Resources (Limits : Resource_Limits);

   --   Display profile selection screen
   procedure Display_Profiles (Profiles : Profile_List);

   --   Display validation progress
   procedure Display_Progress (Message : String; Percent : Natural);

   --   Display validation result
   procedure Display_Result (Code : Exit_Code; Elapsed : Duration);

   --  =========================================================================
   --  Utilities
   --  =========================================================================

   --   Format memory size for display
   function Format_Memory (KB : Natural) return String;

   --   Get user home directory
   function Get_Home_Directory return String;

   --   Check if container runtime is available
   function Is_Container_Available return Boolean;

   --   Get container runtime command (nerdctl or podman)
   function Get_Container_Command return String;

private

   --   Configuration file path
   Config_File : constant String := ".config/nerdsafe-restart/profiles.json";

   --   Default profile name
   Default_Profile_Name : constant String := "system-detected";

end Nerdsafe_TUI;
