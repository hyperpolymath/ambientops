--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Safety_Invariant - Implementation of SPARK proof specifications

pragma SPARK_Mode (On);

package body Safety_Invariant
  with Refined_State => (Global_State => (Active_Recovery_Point,
                                          Last_Operation_Had_Recovery,
                                          Operations_Since_Recovery))
is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant Definition
   --  ═══════════════════════════════════════════════════════════════════════

   function Recovery_Point_Available return Boolean is
     (Valid_Snapshot (Active_Recovery_Point));

   function Invariant_Holds return Boolean is
     (Last_Operation_Had_Recovery and
      (Operations_Since_Recovery = 0 or Recovery_Point_Available));

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant State Updates
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Record_Recovery_Point_Created (ID : Snapshot_ID) is
   begin
      Active_Recovery_Point := ID;
      Operations_Since_Recovery := 0;
      Last_Operation_Had_Recovery := True;
   end Record_Recovery_Point_Created;

   procedure Record_Operation_Performed is
   begin
      Operations_Since_Recovery := Operations_Since_Recovery + 1;
      Last_Operation_Had_Recovery := True;
   end Record_Operation_Performed;

   procedure Record_Rollback_Performed (To : Snapshot_ID) is
   begin
      Active_Recovery_Point := To;
      Operations_Since_Recovery := 0;
   end Record_Rollback_Performed;

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant Verification Lemmas
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Lemma_Create_Before_Modify is
   begin
      --  Trivially true from the definitions
      null;
   end Lemma_Create_Before_Modify;

   procedure Lemma_Recovery_Enables_Rollback is
   begin
      --  Trivially true: Can_Perform_Rollback = Recovery_Point_Available
      null;
   end Lemma_Recovery_Enables_Rollback;

   procedure Lemma_Invariant_Preserved_By_Safe_Ops is
   begin
      --  After a safe operation:
      --  - Last_Operation_Had_Recovery is set to True by Record_Operation_Performed
      --  - Recovery_Point_Available remains true (we don't delete the recovery point)
      --  Therefore Invariant_Holds remains true
      null;
   end Lemma_Invariant_Preserved_By_Safe_Ops;

end Safety_Invariant;
