-------------------------------------------------------------------------------
--  nano-aider - Options Discovery and Management
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

package Nano_Aider.Options is

   --  String access type for dynamic strings
   type String_Access is access constant String;

   --  Option value types
   type Option_Value_Type is
     (Opt_Boolean,
      Opt_Integer,
      Opt_String,
      Opt_Color,
      Opt_Key_Binding,
      Opt_Regex,
      Opt_Enum);

   --  Single option record
   type Option_Record is record
      Name          : String_Access;
      Description   : String_Access;
      Value_Type    : String_Access;
      Default_Value : String_Access;
      Current_Value : String_Access;
      Is_Hidden     : Boolean;
      Is_Deprecated : Boolean;
      Nano_Version  : String_Access;  -- Version when introduced
      Micro_Support : Boolean;        -- Also available in micro
   end record;

   --  Category record
   type Category_Record is record
      Name         : String_Access;
      Description  : String_Access;
      Option_Count : Natural;
   end record;

   --  Arrays
   type Option_Array is array (Natural range <>) of Option_Record;
   type Category_Array is array (Natural range <>) of Category_Record;

   --  Discovery
   procedure Discover_All;
   procedure List_All_Options;

   --  Categories
   function Get_Categories return Category_Array;
   function Category_Count return Natural;

   --  Options
   function Get_Options_For_Category (Cat_Index : Natural) return Option_Array;
   function Get_Option (Cat_Index, Opt_Index : Natural) return Option_Record;
   function Option_Count (Cat_Index : Natural) return Natural;

   --  Search
   procedure Search (Query : String);
   function Search_Results_Count return Natural;

   --  Modification
   procedure Set_Option_Value (Cat_Index, Opt_Index : Natural; Value : String);
   procedure Reset_Option (Cat_Index, Opt_Index : Natural);
   procedure Reset_All;

end Nano_Aider.Options;
