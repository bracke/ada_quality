with Ada_Quality.Types;

--  Assessment lifecycle capability for an open storage handle.
package Ada_Quality.Storage.Assessments is
   function Start
     (Item               : in out Store;
      Project_Id         : Positive;
      Source_Fingerprint : String;
      Policy_Fingerprint : String) return Positive;
   --  Atomically create a running assessment and its start event.

   function Publish
     (Item : in out Store; Value : Ada_Quality.Types.Assessment) return Positive;
   --  Validate and atomically publish complete terminal evidence.

   procedure Add_Alias
     (Item : in out Store; Run_Id : Positive; Name : String);
   --  Assign a globally unique append-only alias to a completed assessment.

   procedure Interrupt
     (Item : in out Store; Run_Id : Positive; Reason : String);
   --  Atomically interrupt a running assessment and record Reason.

   procedure Recover (Item : in out Store; Count : out Natural);
   --  Interrupt every stale running assessment and return the number recovered.

   function History
     (Item : in out Store; Project_Id : Natural := 0)
      return History_Vectors.Vector;
   --  Return assessment metadata, optionally filtered by project identity.

   function Results
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector;
   --  Return persisted indicator-result rows, optionally filtered by run.

   function Measurements
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector;
   --  Return persisted typed-measurement rows, optionally filtered by run.

   function Findings
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector;
   --  Return persisted finding rows, optionally filtered by run.

   function Executions
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector;
   --  Return persisted external-execution rows, optionally filtered by run.

   function Events
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector;
   --  Return persisted lifecycle events, optionally filtered by run.
end Ada_Quality.Storage.Assessments;
