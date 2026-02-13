--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

pragma SPARK_Mode (Off);  -- Body contains runtime registry

package body Backend_Interface is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Backend Registry State
   --  ═══════════════════════════════════════════════════════════════════════

   type Backend_Entry is record
      PM_Type : Package_Manager_Type := Platform_Detection.None;
      Backend : Backend_Access := null;
   end record;

   Max_Backends : constant := 50;
   type Backend_Array is array (1 .. Max_Backends) of Backend_Entry;

   Registry      : Backend_Array;
   Registry_Size : Natural := 0;

   Primary_Backend_Cache : Backend_Access := null;
   Primary_Detected      : Boolean := False;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Registry Operations
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Register_Backend
     (PM_Type : Package_Manager_Type;
      Backend : Backend_Access)
   is
   begin
      if Registry_Size < Max_Backends then
         Registry_Size := Registry_Size + 1;
         Registry (Registry_Size) := (PM_Type => PM_Type, Backend => Backend);
      end if;
   end Register_Backend;

   function Get_Backend (PM_Type : Package_Manager_Type) return Backend_Access is
   begin
      for I in 1 .. Registry_Size loop
         if Registry (I).PM_Type = PM_Type then
            return Registry (I).Backend;
         end if;
      end loop;
      return null;
   end Get_Backend;

   function Get_Primary_Backend return Backend_Access is
      use Platform_Detection;
      Platform : Platform_Info;
   begin
      --  Return cached result if available
      if Primary_Detected then
         return Primary_Backend_Cache;
      end if;

      --  Detect platform and find appropriate backend
      Platform := Detect_Platform;

      --  Try primary package manager first
      Primary_Backend_Cache := Get_Backend (Platform.Primary_PM);

      --  If primary not available, try alternatives in order of preference
      if Primary_Backend_Cache = null then
         --  Prefer Guix, then Nix
         if Platform.Has_Guix then
            Primary_Backend_Cache := Get_Backend (Guix);
         elsif Platform.Has_Nix then
            Primary_Backend_Cache := Get_Backend (Nix);
         end if;
      end if;

      Primary_Detected := True;
      return Primary_Backend_Cache;
   end Get_Primary_Backend;

   function List_Available_Backends return Package_Manager_Type is
   begin
      --  Return first available backend type
      --  Full implementation would return an array
      if Registry_Size > 0 then
         return Registry (1).PM_Type;
      else
         return Platform_Detection.None;
      end if;
   end List_Available_Backends;

end Backend_Interface;
