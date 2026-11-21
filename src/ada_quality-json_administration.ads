with Ada_Quality.Artifact_Signing;
with Ada_Quality.Checks;
with Ada_Quality.Command_Models;
with Ada_Quality.Policy;
with Ada_Quality.Storage;

--  Administrative JSON contracts and stable error envelopes.
package Ada_Quality.JSON_Administration is
   function Render_Doctor
     (Items : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Maximum_Failures : Natural := 0;
      Failure_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String;

   function Render_Waivers
     (Items : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
      Maximum_Invalid : Natural := 0;
      Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last;
      Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String;

   function Render_Doctor_Batch
     (Items : Ada_Quality.Command_Models.Diagnostic_Report_Vectors.Vector;
      Global_Checks : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector :=
        Ada_Quality.Command_Models.Diagnostic_Vectors.Empty_Vector;
      Maximum_Failures : Natural := 0;
      Pretty : Boolean := False) return String;

   function Render_Waiver_Batch
     (Items : Ada_Quality.Command_Models.Waiver_Report_Vectors.Vector;
      Maximum_Invalid : Natural := 0;
      Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last;
      Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String;

   function Render_Error
     (Code, Message, Command : String;
      Exit_Status : Natural;
      Pretty : Boolean := False) return String;

   function Render_Command_Result
     (Command, Detail : String;
      Success : Boolean;
      Pretty : Boolean := False) return String;

   function Render_String_List
     (Kind, Member : String;
      Items : Ada_Quality.Command_Models.String_Vectors.Vector;
      Pretty : Boolean := False) return String;

   function Render_Policy
     (Item : Ada_Quality.Policy.Quality_Policy;
      Source : String := "";
      Pretty : Boolean := False) return String;

   function Render_Policy_Diff
     (Left_Name, Right_Name : String;
      Left, Right : Ada_Quality.Policy.Quality_Policy;
      Pretty : Boolean := False) return String;

   function Render_Policy_Impact
     (Before_Name, After_Name : String;
      Items : Ada_Quality.Command_Models.Policy_Impact_Vectors.Vector;
      Pretty : Boolean := False) return String;

   function Render_Signature
     (Item : Ada_Quality.Artifact_Signing.Signature_Info;
      Verified : Boolean;
      Pretty : Boolean := False) return String;

   function Render_Trusted_Keys
     (Items : Ada_Quality.Artifact_Signing.Trusted_Key_Vectors.Vector;
      Pretty : Boolean := False) return String;

   function Render_Retention
     (Items : Ada_Quality.Storage.History_Vectors.Vector;
      Before : String;
      Keep : Natural;
      Pretty : Boolean := False) return String;

   function Render_Merge
     (Sources : Ada_Quality.Storage.Source_Vectors.Vector;
      Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments,
      Added_Aliases : Natural;
      Conflicts : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String;

   function Render_Merge
     (Source : String;
      Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments,
      Added_Aliases : Natural;
      Conflicts : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String;
end Ada_Quality.JSON_Administration;
