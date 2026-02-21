-------------------------------------------------------------------------------
--  nano-aider - Options Test Suite
--  Copyright (C) 2024-2025 Jonathan D.A. Jewell
--  SPDX-License-Identifier: MIT OR AGPL-3.0-or-later
-------------------------------------------------------------------------------

with Ada.Text_IO;
with Nano_Aider.Options;

procedure Test_Options is
   package TIO renames Ada.Text_IO;
   package Opts renames Nano_Aider.Options;

   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if Condition then
         TIO.Put_Line ("  PASS: " & Message);
         Passed := Passed + 1;
      else
         TIO.Put_Line ("  FAIL: " & Message);
         Failed := Failed + 1;
      end if;
   end Assert;

begin
   TIO.Put_Line ("nano-aider Options Test Suite");
   TIO.Put_Line ("=============================");
   TIO.New_Line;

   TIO.Put_Line ("Test: Category Count");
   Assert (Opts.Category_Count = 10, "Should have 10 categories");

   TIO.Put_Line ("Test: Get Categories");
   declare
      Cats : constant Opts.Category_Array := Opts.Get_Categories;
   begin
      Assert (Cats'Length = 10, "Category array length should be 10");
      Assert (Cats (0).Name.all = "Display", "First category should be Display");
   end;

   TIO.Put_Line ("Test: Hidden Options");
   declare
      Hidden : constant Opts.Option_Array := Opts.Get_Options_For_Category (8);
   begin
      Assert (Hidden'Length > 0, "Should have hidden options");
      Assert (Hidden (0).Is_Hidden, "Hidden options should be marked hidden");
   end;

   TIO.Put_Line ("Test: Search");
   Opts.Search ("mini");
   Assert (Opts.Search_Results_Count > 0, "Search for 'mini' should find minibar");

   TIO.New_Line;
   TIO.Put_Line ("=============================");
   TIO.Put_Line ("Results:" & Natural'Image (Passed) & " passed," &
                 Natural'Image (Failed) & " failed");

   if Failed > 0 then
      TIO.Put_Line ("SOME TESTS FAILED");
   else
      TIO.Put_Line ("ALL TESTS PASSED");
   end if;
end Test_Options;
