with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Ada_Quality.Storage;

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
     (Store : in out Ada_Quality.Storage.Store; Pretty : Boolean := False) return String;
   --  Serialize every persisted project, assessment, detail, and regression.
   --  @param Store Open persistent store to read.
   --  @param Pretty Whether to indent the resulting document.
   --  @return Complete archive JSON document.
end Ada_Quality.JSON;
