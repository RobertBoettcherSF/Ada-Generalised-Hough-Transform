with Ada.Text_IO; use Ada.Text_IO;
with Ada.Numerics; use Ada.Numerics;
with Generalised_Hough_Transform; use Generalised_Hough_Transform;

procedure Tests is

   -- Test Output Formatting Helper
   procedure Assert_Test (Condition : Boolean; Message : String) is
   begin
      if Condition then
         Put_Line ("      PASS: " & Message);
      else
         Put_Line ("      FAIL: " & Message);
         -- In a strict CI, we might raise an error here. 
         -- For terminal visibility, we print and continue to execute other tests.
      end if;
   end Assert_Test;

   Empty_Edges : constant Edge_Point_Array (1 .. 0) := (others => (Location => (0.0,0.0), Gradient_Direction => 0.0));
   Ref_Origin  : constant Point := (0.0, 0.0);
   Table       : R_Table;
   Result      : Detection_Result;

begin
   Put_Line ("===============================================");
   Put_Line (" GENERALISED HOUGH TRANSFORM TEST SUITE");
   Put_Line ("===============================================");

   Put_Line ("TEST 1 - Exception Handling: Empty Template");
   Put_Line ("  1.1 Assume code crashes or ignores empty template building");
   begin
      Table := Build_R_Table (Empty_Edges, Ref_Origin);
      Assert_Test (False, "Should have raised Invalid_Data_Error");
   exception
      when Invalid_Data_Error => Assert_Test (True, "Raised Invalid_Data_Error appropriately");
   end;

   Put_Line ("TEST 2 - Exception Handling: Empty Target Array");
   Put_Line ("  2.1 Assume code crashes during accumulation loop without data");
   begin
      -- Must have a dummy valid table for this test
      Table := Build_R_Table ((1 => (Location => (1.0, 1.0), Gradient_Direction => 0.0)), Ref_Origin);
      Result := Detect_Translation (Empty_Edges, Table, 0, 10, 0, 10);
      Assert_Test (False, "Should have raised Invalid_Data_Error");
   exception
      when Invalid_Data_Error => Assert_Test (True, "Raised Invalid_Data_Error correctly");
   end;

   Put_Line ("TEST 3 - R-Table Single Point Logic");
   Put_Line ("  3.1 Assume R-Table miscalculates radius and angle");
   declare
      T_Edges : Edge_Point_Array := (1 => (Location => (10.0, 0.0), Gradient_Direction => Pi));
      T_Table : R_Table;
   begin
      T_Table := Build_R_Table (T_Edges, Ref_Origin);
      Assert_Test (Natural(T_Table.Entries(180).Length) = 1, "Correctly placed at 180 degrees index");
      Assert_Test (T_Table.Entries(180).First_Element.Radius = 10.0, "Radius calculated properly");
   end;

   Put_Line ("TEST 4 - R-Table Angle Wrapping");
   Put_Line ("  4.1 Assume negative radians crash the indexer");
   declare
      T_Edges : Edge_Point_Array := (1 => (Location => (0.0, 10.0), Gradient_Direction => -Pi / 2.0));
      T_Table : R_Table;
   begin
      T_Table := Build_R_Table (T_Edges, Ref_Origin);
      -- -90 degrees wraps to 270 degrees
      Assert_Test (Natural(T_Table.Entries(270).Length) = 1, "Handled negative rad wrap to 270 degrees");
   end;

   Put_Line ("TEST 5 - Multiple Points Collision on R-Table");
   Put_Line ("  5.1 Assume R-Table overwrites points with same gradient");
   declare
      T_Edges : Edge_Point_Array := (
         1 => (Location => (5.0, 5.0), Gradient_Direction => 0.0),
         2 => (Location => (10.0, 10.0), Gradient_Direction => 0.0)
      );
      T_Table : R_Table;
   begin
      T_Table := Build_R_Table (T_Edges, Ref_Origin);
      Assert_Test (Natural(T_Table.Entries(0).Length) = 2, "Stored both points at 0 degrees index");
   end;

   Put_Line ("TEST 6 - Translation variant: Perfect match");
   Put_Line ("  6.1 Assume system cannot detect pure translation");
   declare
      T_Edges : Edge_Point_Array := (
         1 => (Location => (5.0, 0.0), Gradient_Direction => 0.0),
         2 => (Location => (0.0, 5.0), Gradient_Direction => Pi/2.0)
      );
      Target  : Edge_Point_Array := (
         1 => (Location => (15.0, 10.0), Gradient_Direction => 0.0),
         2 => (Location => (10.0, 15.0), Gradient_Direction => Pi/2.0)
      );
      T_Table : R_Table;
   begin
      T_Table := Build_R_Table (T_Edges, Ref_Origin);
      Result := Detect_Translation (Target, T_Table, 0, 20, 0, 20);
      Assert_Test (Result.Votes = 2, "Detected both votes");
      Assert_Test (Result.Reference_Point.X = 10.0 and Result.Reference_Point.Y = 10.0, "Center detected at (10,10)");
   end;

   Put_Line ("TEST 7 - Out of Bounds Target Points");
   Put_Line ("  7.1 Assume points voting outside Min/Max bounds raise Constraint_Error");
   declare
      T_Table : R_Table := Build_R_Table ((1 => (Location => (5.0, 0.0), Gradient_Direction => 0.0)), Ref_Origin);
      -- Target will vote for center at (100, 100) which is out of bounds
      Target  : Edge_Point_Array := ((Location => (105.0, 100.0), Gradient_Direction => 0.0));
   begin
      Result := Detect_Translation (Target, T_Table, 0, 10, 0, 10);
      Assert_Test (Result.Votes = 0, "Silently discarded out of bound votes without crashing");
   end;

   Put_Line ("TEST 8 - Error Handling: Invalid Min/Max Bounds");
   Put_Line ("  8.1 Assume Min > Max array allocations crash ungracefully");
   begin
      Result := Detect_Translation (Empty_Edges, Table, 10, 0, 0, 10);
      Assert_Test (False, "Should raise Invalid_Bounds_Error");
   exception
      when Invalid_Bounds_Error => Assert_Test (True, "Raised Invalid_Bounds_Error gracefully");
   end;

   Put_Line ("TEST 9 - Noise Handling / Scattered match");
   Put_Line ("  9.1 Assume random noise creates false overwhelming peaks");
   declare
      T_Table : R_Table := Build_R_Table ((1 => (Location => (2.0, 0.0), Gradient_Direction => 0.0)), Ref_Origin);
      Target  : Edge_Point_Array := (
         1 => (Location => (2.0, 0.0), Gradient_Direction => Pi),     -- Incorrect gradient
         2 => (Location => (4.0, 4.0), Gradient_Direction => Pi/2.0)  -- Incorrect gradient
      );
   begin
      Result := Detect_Translation (Target, T_Table, 0, 10, 0, 10);
      Assert_Test (Result.Votes = 0, "No false positives from misaligned gradients");
   end;

   Put_Line ("TEST 10 - Extended Variant: Perfect Scale");
   Put_Line ("  10.1 Assume scaling math is incorrect and scaling shifts center incorrectly");
   declare
      T_Edges : Edge_Point_Array := (1 => (Location => (5.0, 0.0), Gradient_Direction => 0.0));
      Target  : Edge_Point_Array := (1 => (Location => (15.0, 5.0), Gradient_Direction => 0.0)); -- Center should be (5,5) at scale 2.0
      T_Table : R_Table := Build_R_Table (T_Edges, Ref_Origin);
      Scales  : Scale_Array := (1.0, 2.0, 3.0);
      Rots    : Rotation_Array := (1 => 0.0);
   begin
      Result := Detect_Extended (Target, T_Table, 0, 20, 0, 20, Scales, Rots);
      Assert_Test (Result.Scale = 2.0, "Scale 2.0 accurately matched");
      Assert_Test (Result.Reference_Point.X = 5.0 and Result.Reference_Point.Y = 5.0, "Scaled Reference point accurate");
   end;

   Put_Line ("TEST 11 - Extended Variant: Perfect Rotation");
   Put_Line ("  11.1 Assume rotation matrix calculations map to wrong quadrants");
   declare
      T_Edges : Edge_Point_Array := (1 => (Location => (10.0, 0.0), Gradient_Direction => 0.0));
      T_Table : R_Table := Build_R_Table (T_Edges, Ref_Origin);
      -- Shape rotated by 90 deg (Pi/2). Gradient also rotates. Point now at (0, 10) relative to origin. Target shifted to (5, 15).
      -- Center should be (5, 5).
      Target  : Edge_Point_Array := (1 => (Location => (5.0, 15.0), Gradient_Direction => Pi/2.0));
      Scales  : Scale_Array := (1 => 1.0);
      Rots    : Rotation_Array := (0.0, Pi/2.0, Pi);
   begin
      Result := Detect_Extended (Target, T_Table, 0, 20, 0, 20, Scales, Rots);
      Assert_Test (Result.Rotation = Pi/2.0, "Rotation Pi/2 accurately matched");
      Assert_Test (Result.Reference_Point.X = 5.0 and Result.Reference_Point.Y = 5.0, "Rotated Reference point accurate");
   end;

   Put_Line ("TEST 12 - Extended Variant: Combined Scale & Rotation");
   Put_Line ("  12.1 Assume combining parameters misaligns vectors");
   declare
      T_Edges : Edge_Point_Array := (1 => (Location => (5.0, 0.0), Gradient_Direction => 0.0));
      T_Table : R_Table := Build_R_Table (T_Edges, Ref_Origin);
      -- Scale = 3.0, Rotation = Pi/2. Radius becomes 15. Alpha was 0, becomes Pi/2.
      -- Offset from ref is (0, 15). 
      -- If Target is at (20, 20), Center must be at (20, 5).
      Target  : Edge_Point_Array := (1 => (Location => (20.0, 20.0), Gradient_Direction => Pi/2.0));
      Scales  : Scale_Array := (1.0, 3.0);
      Rots    : Rotation_Array := (0.0, Pi/2.0);
   begin
      Result := Detect_Extended (Target, T_Table, 0, 30, 0, 30, Scales, Rots);
      Assert_Test (Result.Scale = 3.0, "Combined: scale correct");
      Assert_Test (Result.Rotation = Pi/2.0, "Combined: rotation correct");
      Assert_Test (Result.Reference_Point.X = 20.0 and Result.Reference_Point.Y = 5.0, "Combined: reference point correct");
   end;

   Put_Line ("TEST 13 - Extended Variant: Empty Scales array");
   Put_Line ("  13.1 Assume missing scale array forces Division by zero or out of bounds");
   declare
      T_Table : R_Table := Build_R_Table ((1 => (Location => (1.0, 1.0), Gradient_Direction => 0.0)), Ref_Origin);
      Empty_S : Scale_Array (1 .. 0) := (others => 0.0);
      Rots    : Rotation_Array := (1 => 0.0);
      Targ    : Edge_Point_Array := (1 => (Location => (1.0, 1.0), Gradient_Direction => 0.0));
   begin
      Result := Detect_Extended (Targ, T_Table, 0, 10, 0, 10, Empty_S, Rots);
      Assert_Test (False, "Should have raised Invalid_Data_Error");
   exception
      when Invalid_Data_Error => Assert_Test (True, "Handled empty scales securely");
   end;

end Tests;
