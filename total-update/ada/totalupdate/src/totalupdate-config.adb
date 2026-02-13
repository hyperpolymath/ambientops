--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

with Ada.Text_IO;
with Ada.Directories;
with Ada.Environment_Variables;

with TotalUpdate.Logging;

package body TotalUpdate.Config is

   use TotalUpdate.Logging;

   --  Default configuration values
   Default_Check_Interval : constant Duration := 14400.0;  --  4 hours
   Default_Auto_Update    : constant Boolean := False;
   Default_Snapshot       : constant String := "auto";
   Default_Bandwidth      : constant Natural := 0;  --  Unlimited
   Default_Parallel       : constant Positive := 3;

   --  Current configuration state
   type Config_State is record
      Loaded           : Boolean := False;
      Config_Path      : String (1 .. 256) := (others => ' ');
      Path_Length      : Natural := 0;
      Check_Interval   : Duration := Default_Check_Interval;
      Auto_Update      : Boolean := Default_Auto_Update;
      Bandwidth_Limit  : Natural := Default_Bandwidth;
      Max_Parallel     : Positive := Default_Parallel;
   end record;

   State : Config_State;

   function User_Config_Path return String is
      Home : constant String :=
        Ada.Environment_Variables.Value ("HOME", "/root");
   begin
      return Home & "/.config/totalupdate/config.scm";
   end User_Config_Path;

   function System_Config_Path return String is
   begin
      return "/etc/totalupdate/config.scm";
   end System_Config_Path;

   procedure Parse_Config_File (Path : String) is
      --  Simple config parser
      --  Full implementation would use a Scheme parser
      F : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         Warning ("Config file not found: " & Path);
         return;
      end if;

      Info ("Loading configuration from: " & Path);

      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);

      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (F);
         begin
            --  Simple key-value parsing
            --  Real implementation would parse Scheme s-expressions
            null;  --  Placeholder for parsing logic
         end;
      end loop;

      Ada.Text_IO.Close (F);
      State.Loaded := True;

   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Warning ("Error parsing config file: " & Path);
   end Parse_Config_File;

   procedure Load (Path : String) is
   begin
      State.Config_Path (1 .. Path'Length) := Path;
      State.Path_Length := Path'Length;
      Parse_Config_File (Path);
   end Load;

   procedure Load_Default is
      User_Path   : constant String := User_Config_Path;
      System_Path : constant String := System_Config_Path;
   begin
      --  Try user config first
      if Ada.Directories.Exists (User_Path) then
         Load (User_Path);
      elsif Ada.Directories.Exists (System_Path) then
         Load (System_Path);
      else
         Info ("No config file found, using defaults");
         State.Loaded := True;
      end if;
   end Load_Default;

   procedure Reload is
   begin
      if State.Path_Length > 0 then
         Parse_Config_File (State.Config_Path (1 .. State.Path_Length));
      else
         Load_Default;
      end if;
   end Reload;

   function Get_Check_Interval return Duration is
   begin
      return State.Check_Interval;
   end Get_Check_Interval;

   function Get_Auto_Update return Boolean is
   begin
      return State.Auto_Update;
   end Get_Auto_Update;

   function Get_Snapshot_Method return String is
   begin
      return Default_Snapshot;
   end Get_Snapshot_Method;

   function Get_Bandwidth_Limit return Natural is
   begin
      return State.Bandwidth_Limit;
   end Get_Bandwidth_Limit;

   function Get_Max_Parallel_Downloads return Positive is
   begin
      return State.Max_Parallel;
   end Get_Max_Parallel_Downloads;

   function Is_Loaded return Boolean is
   begin
      return State.Loaded;
   end Is_Loaded;

   procedure Set_Check_Interval (Interval : Duration) is
   begin
      State.Check_Interval := Interval;
   end Set_Check_Interval;

   procedure Set_Auto_Update (Enabled : Boolean) is
   begin
      State.Auto_Update := Enabled;
   end Set_Auto_Update;

end TotalUpdate.Config;
