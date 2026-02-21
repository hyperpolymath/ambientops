--  Symlink_Manager - Cross-platform symbolic link management for Ada
--
--  SPDX-License-Identifier: PMPL-1.0
--  Copyright (C) 2025 Hyper Polymath

with Ada.Directories;
with GNAT.OS_Lib;

package body Symlink_Manager is

   use Ada.Directories;

   ----------------------
   -- Is_Symbolic_Link --
   ----------------------

   function Is_Symbolic_Link (Path : String) return Boolean is
   begin
      if not Exists (Path) then
         return False;
      end if;

      return GNAT.OS_Lib.Is_Symbolic_Link (Path);
   exception
      when others =>
         return False;
   end Is_Symbolic_Link;

   ---------------------
   -- Get_Link_Target --
   ---------------------

   function Get_Link_Target (Link_Path : String) return String is
      use GNAT.OS_Lib;
      Buffer : String (1 .. Max_Path_Length);
      Last   : Natural;
   begin
      if not Is_Symbolic_Link (Link_Path) then
         return "";
      end if;

      Last := GNAT.OS_Lib.Read_Symbolic_Link (Link_Path, Buffer);
      if Last > 0 then
         return Buffer (1 .. Last);
      else
         return "";
      end if;
   exception
      when others =>
         return "";
   end Get_Link_Target;

   -----------------
   -- Create_Link --
   -----------------

   function Create_Link
     (Link_Path   : String;
      Target_Path : String;
      Error_Msg   : out Unbounded_String) return Boolean
   is
      use GNAT.OS_Lib;
      Success : Boolean;
   begin
      Error_Msg := Null_Unbounded_String;

      --  Validate target exists
      if not Exists (Target_Path) then
         Error_Msg := To_Unbounded_String (
           "Target path does not exist: " & Target_Path);
         return False;
      end if;

      --  Check if link already exists
      if Exists (Link_Path) then
         if Is_Symbolic_Link (Link_Path) then
            if Get_Link_Target (Link_Path) = Target_Path then
               --  Already points to correct target
               return True;
            else
               Error_Msg := To_Unbounded_String (
                 "Link already exists pointing to different target: " &
                 Get_Link_Target (Link_Path));
               return False;
            end if;
         else
            Error_Msg := To_Unbounded_String (
              "Path exists but is not a symbolic link");
            return False;
         end if;
      end if;

      --  Ensure parent directory exists
      declare
         Parent : constant String := Containing_Directory (Link_Path);
      begin
         if Parent'Length > 0 and then not Exists (Parent) then
            Create_Path (Parent);
         end if;
      exception
         when others =>
            Error_Msg := To_Unbounded_String (
              "Failed to create parent directory for link");
            return False;
      end;

      --  Create the symbolic link
      GNAT.OS_Lib.Create_Symbolic_Link (Target_Path, Link_Path, Success);

      if not Success then
         Error_Msg := To_Unbounded_String (
           "Failed to create symbolic link (check permissions or platform support)");
         return False;
      end if;

      return True;
   exception
      when others =>
         Error_Msg := To_Unbounded_String ("Unexpected error creating link");
         return False;
   end Create_Link;

   -----------------
   -- Remove_Link --
   -----------------

   function Remove_Link
     (Link_Path : String;
      Error_Msg : out Unbounded_String) return Boolean
   is
   begin
      Error_Msg := Null_Unbounded_String;

      if not Exists (Link_Path) then
         Error_Msg := To_Unbounded_String ("Path does not exist");
         return False;
      end if;

      if not Is_Symbolic_Link (Link_Path) then
         Error_Msg := To_Unbounded_String (
           "Path exists but is not a symbolic link - refusing to delete");
         return False;
      end if;

      Ada.Directories.Delete_File (Link_Path);
      return True;
   exception
      when others =>
         Error_Msg := To_Unbounded_String ("Failed to remove symbolic link");
         return False;
   end Remove_Link;

   -----------------------
   -- Check_Link_Status --
   -----------------------

   function Check_Link_Status (Link_Path : String) return Link_Info is
      Info : Link_Info;
   begin
      Info.Link_Path := To_Unbounded_String (Link_Path);

      if not Exists (Link_Path) then
         Info.Status := Link_Missing;
         return Info;
      end if;

      if not Is_Symbolic_Link (Link_Path) then
         Info.Status := Link_Not_Link;
         Info.Error_Msg := To_Unbounded_String ("Path is not a symbolic link");
         return Info;
      end if;

      declare
         Target : constant String := Get_Link_Target (Link_Path);
      begin
         Info.Target_Path := To_Unbounded_String (Target);

         if Target = "" then
            Info.Status := Link_Error;
            Info.Error_Msg := To_Unbounded_String ("Could not read link target");
         elsif Exists (Target) then
            Info.Status := Link_Valid;
         else
            Info.Status := Link_Broken;
            Info.Error_Msg := To_Unbounded_String (
              "Target does not exist: " & Target);
         end if;
      end;

      return Info;
   exception
      when others =>
         Info.Status := Link_Error;
         Info.Error_Msg := To_Unbounded_String ("Error checking link status");
         return Info;
   end Check_Link_Status;

   ---------------------
   -- Audit_Directory --
   ---------------------

   function Audit_Directory
     (Directory_Path : String;
      Recursive      : Boolean := False) return Audit_Result
   is
      Result  : Audit_Result;
      Search  : Search_Type;
      Dir_Ent : Directory_Entry_Type;

      procedure Process_Directory (Dir : String) is
         Sub_Search  : Search_Type;
         Sub_Dir_Ent : Directory_Entry_Type;
      begin
         if not Exists (Dir) or else Kind (Dir) /= Directory then
            return;
         end if;

         Start_Search (Sub_Search, Dir, "*", (others => True));

         while More_Entries (Sub_Search) loop
            Get_Next_Entry (Sub_Search, Sub_Dir_Ent);

            declare
               Name : constant String := Simple_Name (Sub_Dir_Ent);
               Path : constant String := Full_Name (Sub_Dir_Ent);
            begin
               if Name /= "." and Name /= ".." then
                  if Is_Symbolic_Link (Path) then
                     Result.Total_Links := Result.Total_Links + 1;

                     declare
                        Info : constant Link_Info := Check_Link_Status (Path);
                     begin
                        case Info.Status is
                           when Link_Valid =>
                              Result.Valid_Links := Result.Valid_Links + 1;
                           when Link_Broken =>
                              Result.Broken_Links := Result.Broken_Links + 1;
                           when Link_Missing =>
                              Result.Missing_Links := Result.Missing_Links + 1;
                           when Link_Not_Link | Link_Error =>
                              Result.Errors := Result.Errors + 1;
                        end case;
                     end;
                  elsif Recursive and then Kind (Path) = Directory then
                     Process_Directory (Path);
                  end if;
               end if;
            end;
         end loop;

         End_Search (Sub_Search);
      exception
         when others =>
            Result.Errors := Result.Errors + 1;
      end Process_Directory;

   begin
      Process_Directory (Directory_Path);
      return Result;
   exception
      when others =>
         Result.Errors := Result.Errors + 1;
         return Result;
   end Audit_Directory;

   ----------------------
   -- Status_To_String --
   ----------------------

   function Status_To_String (Status : Link_Status) return String is
   begin
      case Status is
         when Link_Valid    => return "valid";
         when Link_Broken   => return "broken";
         when Link_Missing  => return "missing";
         when Link_Not_Link => return "not_link";
         when Link_Error    => return "error";
      end case;
   end Status_To_String;

   -------------------
   -- Audit_To_JSON --
   -------------------

   function Audit_To_JSON (Result : Audit_Result) return String is
      function Img (N : Natural) return String is
         S : constant String := Natural'Image (N);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;
   begin
      return "{" &
        """total"": " & Img (Result.Total_Links) & ", " &
        """valid"": " & Img (Result.Valid_Links) & ", " &
        """broken"": " & Img (Result.Broken_Links) & ", " &
        """missing"": " & Img (Result.Missing_Links) & ", " &
        """errors"": " & Img (Result.Errors) &
        "}";
   end Audit_To_JSON;

   ----------------------
   -- Link_Info_To_JSON --
   ----------------------

   function Link_Info_To_JSON (Info : Link_Info) return String is
   begin
      return "{" &
        """link"": """ & To_String (Info.Link_Path) & """, " &
        """target"": """ & To_String (Info.Target_Path) & """, " &
        """status"": """ & Status_To_String (Info.Status) & """, " &
        """error"": """ & To_String (Info.Error_Msg) & """" &
        "}";
   end Link_Info_To_JSON;

end Symlink_Manager;
