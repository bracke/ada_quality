with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Reporting;
with Ada_Quality.Types;

--  Deterministic JSON serialization for assessments and persistent archives.
package Ada_Quality.JSON is
   --  Deterministic JSON serialization for assessments and persistent archives.
   function Render (Item : Ada_Quality.Types.Assessment; Pretty : Boolean := False) return String;
   --  Serialize one assessment using the versioned deterministic JSON contract.
   --  @param Item Assessment to serialize.
   --  @param Pretty Whether to indent the resulting document.
   --  @return Complete JSON document.

   type Batch_Outcome_Status is (Batch_Completed, Batch_Interrupted);
   --  Terminal outcome of one project in a multi-project assessment.

   type Batch_Outcome is record
      Project_Id    : Natural := 0;
      Assessment_Id : Natural := 0;
      Status        : Batch_Outcome_Status := Batch_Interrupted;
      Diagnostic    : Ada.Strings.Unbounded.Unbounded_String;
      Value         : Ada_Quality.Types.Assessment;
   end record;
   --  One completed assessment or interrupted project-local outcome.

   package Batch_Outcome_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Batch_Outcome);

   function Render_Batch
     (Items : Batch_Outcome_Vectors.Vector; Pretty : Boolean := False) return String;
   --  Serialize a multi-project run as one versioned JSON document.

   function Render_Archive
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean := False;
      Max_Output_Bytes : Positive := 268_435_456) return String;
   --  Serialize every persisted project, assessment, detail, and regression.
   --  @param Item Open, bounded, read-only reporting snapshot.
   --  @param Pretty Whether to indent the resulting document.
   --  @param Max_Output_Bytes Maximum serialized archive size.
   --  @return Complete archive JSON document.
   --  @exception Ada_Quality.Reporting.Limit_Error The serialized archive exceeds the output limit.
end Ada_Quality.JSON;
