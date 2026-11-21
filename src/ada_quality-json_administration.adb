with Ada.Strings.Unbounded;
with Ada_Quality.JSON_Support;
with Jsonlib.Documents;

package body Ada_Quality.JSON_Administration is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Command_Models;
   use Jsonlib.Documents;

   function Serialize
     (Doc : Document; Pretty : Boolean) return String
      renames Ada_Quality.JSON_Support.Serialize;

   procedure Append_Diagnostics
     (Doc : in out Document;
      Values : Node;
      Items : Diagnostic_Vectors.Vector;
      Passed : in out Boolean)
   is
   begin
      for Item of Items loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert
              (Object, "name", Doc.New_String (To_String (Item.Name)));
            Doc.Insert (Object, "passed", Doc.New_Boolean (Item.Passed));
            Doc.Insert
              (Object, "detail", Doc.New_String (To_String (Item.Detail)));
            Doc.Append (Values, Object);
            Passed := Passed and Item.Passed;
         end;
      end loop;
   end Append_Diagnostics;

   procedure Append_Waiver
     (Doc : in out Document;
      Values : Node;
      Item : Ada_Quality.Checks.Waiver_Audit_Item)
   is
      Object : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Object, "rule", Doc.New_String (To_String (Item.Rule)));
      Doc.Insert (Object, "target", Doc.New_String (To_String (Item.Target)));
      Doc.Insert (Object, "owner", Doc.New_String (To_String (Item.Owner)));
      Doc.Insert
        (Object, "expires", Doc.New_String (To_String (Item.Expires)));
      Doc.Insert
        (Object, "justification",
         Doc.New_String (To_String (Item.Justification)));
      Doc.Insert
        (Object, "path", Doc.New_String (To_String (Item.Relative_Path)));
      Doc.Insert
        (Object, "line", Doc.New_Integer (Long_Long_Integer (Item.Line)));
      Doc.Insert (Object, "expiring", Doc.New_Boolean (Item.Expiring));
      Doc.Insert
        (Object, "status",
         Doc.New_String
           ((case Item.Status is
               when Ada_Quality.Checks.Waiver_Active  => "active",
               when Ada_Quality.Checks.Waiver_Unused  => "unused",
               when Ada_Quality.Checks.Waiver_Expired => "expired",
               when Ada_Quality.Checks.Waiver_Invalid => "invalid")));
      Doc.Append (Values, Object);
   end Append_Waiver;

   procedure Populate_Policy
     (Doc : in out Document;
      Root : Node;
      Item : Ada_Quality.Policy.Quality_Policy)
   is
   begin
      for Key in Ada_Quality.Policy.Policy_Key loop
         if Ada_Quality.Policy.Is_Boolean (Key) then
            Doc.Insert
              (Root, Ada_Quality.Policy.Name (Key),
               Doc.New_Boolean
                 (Ada_Quality.Policy.Boolean_Value (Item, Key)));
         else
            Doc.Insert
              (Root, Ada_Quality.Policy.Name (Key),
               Doc.New_Integer
                 (Long_Long_Integer
                    (Ada_Quality.Policy.Natural_Value (Item, Key))));
         end if;
      end loop;
   end Populate_Policy;

   function Render_Doctor
     (Items : Diagnostic_Vectors.Vector;
      Maximum_Failures : Natural := 0;
      Failure_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String is separate;
   function Render_Waivers
     (Items : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
      Maximum_Invalid : Natural := 0;
      Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last;
      Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String is separate;
   function Render_Doctor_Batch
     (Items : Diagnostic_Report_Vectors.Vector;
      Global_Checks : Diagnostic_Vectors.Vector :=
        Diagnostic_Vectors.Empty_Vector;
      Maximum_Failures : Natural := 0;
      Pretty : Boolean := False) return String is separate;
   function Render_Waiver_Batch
     (Items : Waiver_Report_Vectors.Vector;
      Maximum_Invalid : Natural := 0;
      Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last;
      Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String is separate;
   function Render_Error
     (Code, Message, Command : String;
      Exit_Status : Natural;
      Pretty : Boolean := False) return String is separate;
   function Render_Command_Result
     (Command, Detail : String;
      Success : Boolean;
      Pretty : Boolean := False) return String is separate;
   function Render_String_List
     (Kind, Member : String;
      Items : String_Vectors.Vector;
      Pretty : Boolean := False) return String is separate;
   function Render_Policy
     (Item : Ada_Quality.Policy.Quality_Policy;
      Source : String := "";
      Pretty : Boolean := False) return String is separate;
   function Render_Policy_Diff
     (Left_Name, Right_Name : String;
      Left, Right : Ada_Quality.Policy.Quality_Policy;
      Pretty : Boolean := False) return String is separate;
   function Render_Policy_Impact
     (Before_Name, After_Name : String;
      Items : Policy_Impact_Vectors.Vector;
      Pretty : Boolean := False) return String is separate;
   function Render_Signature
     (Item : Ada_Quality.Artifact_Signing.Signature_Info;
      Verified : Boolean;
      Pretty : Boolean := False) return String is separate;
   function Render_Trusted_Keys
     (Items : Ada_Quality.Artifact_Signing.Trusted_Key_Vectors.Vector;
      Pretty : Boolean := False) return String is separate;
   function Render_Retention
     (Items : Ada_Quality.Storage.History_Vectors.Vector;
      Before : String;
      Keep : Natural;
      Pretty : Boolean := False) return String is separate;

   function Render_Merge
     (Sources : Ada_Quality.Storage.Source_Vectors.Vector;
      Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments,
      Added_Aliases : Natural;
      Conflicts : Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String
   is
      Doc          : Document;
      Root         : constant Node := Doc.New_Object;
      Values       : constant Node := Doc.New_Array;
      Source_Nodes : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("database-merge"));
      for Source of Sources loop
         Doc.Append (Source_Nodes, Doc.New_String (To_String (Source)));
      end loop;
      Doc.Insert (Root, "sources", Source_Nodes);
      Doc.Insert (Root, "dry_run", Doc.New_Boolean (Dry_Run));
      Doc.Insert
        (Root, "added_projects",
         Doc.New_Integer (Long_Long_Integer (Added_Projects)));
      Doc.Insert
        (Root, "added_assessments",
         Doc.New_Integer (Long_Long_Integer (Added_Assessments)));
      Doc.Insert
        (Root, "reused_assessments",
         Doc.New_Integer (Long_Long_Integer (Reused_Assessments)));
      Doc.Insert
        (Root, "added_aliases",
         Doc.New_Integer (Long_Long_Integer (Added_Aliases)));
      for Item of Conflicts loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert
              (Object, "name", Doc.New_String (To_String (Item.Name)));
            Doc.Insert
              (Object, "detail", Doc.New_String (To_String (Item.Detail)));
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "conflicts", Values);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Merge;

   function Render_Merge
     (Source : String;
      Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments,
      Added_Aliases : Natural;
      Conflicts : Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String
   is
      Sources : Ada_Quality.Storage.Source_Vectors.Vector;
   begin
      Sources.Append (To_Unbounded_String (Source));
      return Render_Merge
        (Sources, Dry_Run, Added_Projects, Added_Assessments,
         Reused_Assessments, Added_Aliases, Conflicts, Pretty);
   end Render_Merge;
end Ada_Quality.JSON_Administration;
