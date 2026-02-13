--  SPDX-License-Identifier: AGPL-3.0-or-later
--  SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

--  Safety_Invariant - SPARK proof specifications for the safety invariant
--
--  This package contains the formal specification of the critical invariant:
--
--  ╔═══════════════════════════════════════════════════════════════════════════╗
--  ║  INVARIANT: Every modifying operation MUST be preceded by a recovery     ║
--  ║             point. The system can ALWAYS roll back to a known-good state.║
--  ╚═══════════════════════════════════════════════════════════════════════════╝
--
--  SPARK Proof Level: 2 (Gold)
--  - All preconditions and postconditions are verified
--  - No runtime checks can fail
--  - Memory safety is guaranteed
--
--  To verify: gnatprove -P dnfinition.gpr --level=2

pragma SPARK_Mode (On);

with Reversibility_Types; use Reversibility_Types;

package Safety_Invariant
  with Abstract_State => Global_State,
       Initializes    => Global_State
is

   --  ═══════════════════════════════════════════════════════════════════════
   --  Ghost State for Formal Verification
   --  ═══════════════════════════════════════════════════════════════════════

   --  These ghost variables track invariant state for SPARK verification.
   --  They have no runtime representation.

   Active_Recovery_Point : Snapshot_ID := Null_Snapshot
     with Ghost;
   --  The currently active recovery point (if any)

   Last_Operation_Had_Recovery : Boolean := True
     with Ghost;
   --  True if the last modifying operation had a recovery point

   Operations_Since_Recovery : Natural := 0
     with Ghost;
   --  Count of operations since last recovery point creation

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant Definition
   --  ═══════════════════════════════════════════════════════════════════════

   function Recovery_Point_Available return Boolean
     with Ghost,
          Post => Recovery_Point_Available'Result =
                  Valid_Snapshot (Active_Recovery_Point);
   --  True if a recovery point is currently available

   function Invariant_Holds return Boolean
     with Ghost,
          Post => Invariant_Holds'Result =
                  (Last_Operation_Had_Recovery and
                   (Operations_Since_Recovery = 0 or
                    Recovery_Point_Available));
   --  The main invariant: every operation has a recovery point

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant Predicates (for preconditions)
   --  ═══════════════════════════════════════════════════════════════════════

   function Can_Perform_Modification return Boolean is
     (Recovery_Point_Available)
     with Ghost;
   --  Predicate: can we perform a modifying operation?

   function Can_Perform_Rollback return Boolean is
     (Recovery_Point_Available)
     with Ghost;
   --  Predicate: can we perform a rollback?

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant State Updates (called by Safety_Boundary)
   --  ═══════════════════════════════════════════════════════════════════════

   procedure Record_Recovery_Point_Created (ID : Snapshot_ID)
     with Ghost,
          Pre  => Valid_Snapshot (ID),
          Post => Recovery_Point_Available and
                  Active_Recovery_Point = ID and
                  Operations_Since_Recovery = 0;
   --  Record that a recovery point was created

   procedure Record_Operation_Performed
     with Ghost,
          Pre  => Can_Perform_Modification,
          Post => Operations_Since_Recovery = Operations_Since_Recovery'Old + 1 and
                  Last_Operation_Had_Recovery = True;
   --  Record that a modifying operation was performed

   procedure Record_Rollback_Performed (To : Snapshot_ID)
     with Ghost,
          Pre  => Valid_Snapshot (To),
          Post => Operations_Since_Recovery = 0;
   --  Record that a rollback was performed

   --  ═══════════════════════════════════════════════════════════════════════
   --  Invariant Verification Lemmas
   --  ═══════════════════════════════════════════════════════════════════════

   --  These lemmas are proved by SPARK to establish key properties.

   procedure Lemma_Create_Before_Modify
     with Ghost,
          Pre  => not Recovery_Point_Available,
          Post => not Can_Perform_Modification;
   --  Lemma: Without a recovery point, modifications are blocked

   procedure Lemma_Recovery_Enables_Rollback
     with Ghost,
          Pre  => Recovery_Point_Available,
          Post => Can_Perform_Rollback;
   --  Lemma: With a recovery point, rollback is always possible

   procedure Lemma_Invariant_Preserved_By_Safe_Ops
     with Ghost,
          Pre  => Invariant_Holds and Recovery_Point_Available,
          Post => Invariant_Holds;
   --  Lemma: The invariant is preserved by safe operations

end Safety_Invariant;
