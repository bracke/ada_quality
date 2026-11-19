with Ada.Calendar;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.History_Data;
with Ada_Quality.Types;

--  AQ-WAIVER: SRC-03 target=project_selected owner=aq expires=2099-12-31 justification=streamed-archive-render
package body Ada_Quality.Archive_JSON is
   use Ada.Strings.Unbounded;

   function Render
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean;
      Max_Output_Bytes : Positive;
      Project_Id       : Natural;
      Project_Tag      : String;
      Since_Time       : Ada_Quality.Reporting.Optional_Timestamp;
      Until_Time       : Ada_Quality.Reporting.Optional_Timestamp) return String
   is
      Buffer : Unbounded_String;

      type Container_State is record
         First : Boolean := True;
      end record;
      Stack : array (Positive range 1 .. 8) of Container_State;
      Depth : Natural := 0;

      procedure Put (Text : String) is
      begin
         if Text'Length > Max_Output_Bytes - Length (Buffer) then
            raise Ada_Quality.Reporting.Limit_Error with
              "archive JSON exceeds the output limit of" &
              Positive'Image (Max_Output_Bytes) & " bytes";
         end if;
         Append (Buffer, Text);
      end Put;

      procedure Put (Value : Character) is
      begin
         if Length (Buffer) = Max_Output_Bytes then
            raise Ada_Quality.Reporting.Limit_Error with
              "archive JSON exceeds the output limit of" &
              Positive'Image (Max_Output_Bytes) & " bytes";
         end if;
         Append (Buffer, Value);
      end Put;

      procedure Indent is
      begin
         if Pretty then
            Put (Character'Val (10));
            for Index in 1 .. Depth * 2 loop
               Put (' ');
            end loop;
         end if;
      end Indent;

      procedure Before_Item is
      begin
         if Stack (Depth).First then
            Stack (Depth).First := False;
         else
            Put (',');
         end if;
         Indent;
      end Before_Item;

      procedure Put_JSON_String (Text : String) is
         Hex : constant String := "0123456789abcdef";
      begin
         Put ('"');
         for Value of Text loop
            case Value is
               when '"' => Put ("\""");
               when '\' => Put ("\\");
               when Character'Val (8)  => Put ("\b");
               when Character'Val (9)  => Put ("\t");
               when Character'Val (10) => Put ("\n");
               when Character'Val (12) => Put ("\f");
               when Character'Val (13) => Put ("\r");
               when Character'Val (0) .. Character'Val (7) |
                    Character'Val (11) |
                    Character'Val (14) .. Character'Val (31) =>
                  Put ("\u00");
                  Put (Hex (Character'Pos (Value) / 16 + 1));
                  Put (Hex (Character'Pos (Value) mod 16 + 1));
               when others => Put (Value);
            end case;
         end loop;
         Put ('"');
      end Put_JSON_String;

      procedure Open_Root is
      begin
         Put ('{');
         Depth := 1;
         Stack (Depth).First := True;
      end Open_Root;

      procedure Member (Name : String) is
      begin
         Before_Item;
         Put_JSON_String (Name);
         Put ((if Pretty then ": " else ":"));
      end Member;

      procedure Open_Array_Member (Name : String) is
      begin
         Member (Name);
         Put ('[');
         Depth := Depth + 1;
         Stack (Depth).First := True;
      end Open_Array_Member;

      procedure Open_Object_Element is
      begin
         Before_Item;
         Put ('{');
         Depth := Depth + 1;
         Stack (Depth).First := True;
      end Open_Object_Element;

      procedure Close_Container (Symbol : Character) is
      begin
         if not Stack (Depth).First and then Pretty then
            Depth := Depth - 1;
            Indent;
            Depth := Depth + 1;
         end if;
         Put (Symbol);
         Depth := Depth - 1;
      end Close_Container;

      procedure String_Member (Name, Value : String) is
      begin
         Member (Name);
         Put_JSON_String (Value);
      end String_Member;

      procedure Integer_Member (Name : String; Value : Long_Long_Integer) is
      begin
         Member (Name);
         Put (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Value), Ada.Strings.Both));
      end Integer_Member;

      procedure Boolean_Member (Name : String; Value : Boolean) is
      begin
         Member (Name);
         Put ((if Value then "true" else "false"));
      end Boolean_Member;

      procedure Tags_Member (Value : String) is
         Start : Natural := (if Value'Length = 0 then 0 else Value'First);
      begin
         Member ("tags");
         Put ('[');
         Depth := Depth + 1;
         Stack (Depth).First := True;
         while Start /= 0 and then Start <= Value'Last loop
            declare Stop : Natural := Ada.Strings.Fixed.Index (Value, ",", From => Start); begin
               if Stop = 0 then Stop := Value'Last + 1; end if;
               Before_Item;
               Put_JSON_String (Value (Start .. Stop - 1));
               Start := Stop + 1;
            end;
         end loop;
         Close_Container (']');
      end Tags_Member;

      use type Ada.Calendar.Time;

      function Time_Selected
        (Value : Ada_Quality.Reporting.Optional_Timestamp) return Boolean is
        ((not Since_Time.Present or else
          (Value.Present and then Value.Value >= Since_Time.Value)) and then
         (not Until_Time.Present or else
          (Value.Present and then Value.Value <= Until_Time.Value)));

      All_Projects : constant Ada_Quality.Reporting.Project_Vectors.Vector :=
        Ada_Quality.Reporting.Projects (Item, Include_Removed => True);
      All_Runs : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
        Ada_Quality.Reporting.Runs (Item);
      All_History : constant Ada_Quality.History_Data.History_Vectors.Vector :=
        Ada_Quality.Reporting.History_Items (Item);
      Project_Rows : Ada_Quality.Reporting.Project_Vectors.Vector;
      Run_Rows : Ada_Quality.History_Data.History_Vectors.Vector;

      function Run_Selected (Id : Natural) return Boolean is
      begin
         for Run of Run_Rows loop
            if Run.Id = Id then return True; end if;
         end loop;
         return False;
      end Run_Selected;

      function Latest_Selected_Run (Owner : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Run of Run_Rows loop
            if Run.Project_Id = Owner then Result := Run.Id; end if;
         end loop;
         return Result;
      end Latest_Selected_Run;

      procedure Emit_Assessments is
      begin
         Open_Array_Member ("assessments");
         for Run of Run_Rows loop
            Open_Object_Element;
            Integer_Member ("id", Long_Long_Integer (Run.Id));
            String_Member ("policy_fingerprint", To_String (Run.Policy_Fingerprint));
            Integer_Member ("project_id", Long_Long_Integer (Run.Project_Id));
            String_Member ("source_fingerprint", To_String (Run.Source_Fingerprint));
            String_Member ("status", To_String (Run.Status));
            String_Member ("summary", To_String (Run.Summary));
            String_Member ("toolchain_fingerprint", To_String (Run.Toolchain_Fingerprint));
            Close_Container ('}');
         end loop;
         Close_Container (']');
      end Emit_Assessments;

      procedure Emit_Comparisons is
      begin
         Open_Array_Member ("comparisons");
         for Project of Project_Rows loop
            declare
               Current_Id : constant Natural := Latest_Selected_Run (Project.Id);
            begin
               if Current_Id > 0 then
                  declare
                     Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
                       Ada_Quality.Reporting.Compare_Project (Item, Project.Id, Current_Id);
                     Selection : constant Ada_Quality.History.Comparison_Selection := Comparison.Selection;
                  begin
                     if Selection.Baseline_Id = 0 or else Run_Selected (Selection.Baseline_Id) then
                        Open_Object_Element;
                        Integer_Member ("baseline_id", Long_Long_Integer (Selection.Baseline_Id));
                        Integer_Member ("current_id", Long_Long_Integer (Selection.Current_Id));
                        Boolean_Member ("policy_changed", Selection.Policy_Changed);
                        Integer_Member ("project_id", Long_Long_Integer (Project.Id));
                        String_Member ("status", Ada_Quality.History.Image (Selection.Status));
                        Close_Container ('}');
                     end if;
                  end;
               end if;
            end;
         end loop;
         Close_Container (']');
      end Emit_Comparisons;

      procedure Emit_Events is
         procedure Emit (Event : Ada_Quality.History_Data.Detail_Info) is
         begin
            Open_Object_Element;
            Integer_Member ("assessment_id", Long_Long_Integer (Event.Run_Id));
            Integer_Member ("id", Long_Long_Integer (Event.Id));
            String_Member ("kind", To_String (Event.Kind));
            String_Member ("state", To_String (Event.State));
            String_Member ("summary", To_String (Event.Summary));
            Close_Container ('}');
         end Emit;
      begin
         Open_Array_Member ("events");
         for Run of Run_Rows loop
            Ada_Quality.Reporting.Visit_Details
              (Item, Run.Id, Ada_Quality.Reporting.Event_Details, Emit'Access);
         end loop;
         Close_Container (']');
      end Emit_Events;

      procedure Emit_Executions is
         procedure Emit (Execution : Ada_Quality.Reporting.Execution_Record) is
         begin
            Open_Object_Element;
            Integer_Member ("assessment_id", Long_Long_Integer (Execution.Run_Id));
            String_Member ("command", To_String (Execution.Command));
            Integer_Member ("exit_code", Long_Long_Integer (Execution.Exit_Code));
            Integer_Member ("id", Long_Long_Integer (Execution.Id));
            Integer_Member ("output_bytes", Execution.Output_Bytes);
            String_Member ("output_digest", To_String (Execution.Output_Digest));
            String_Member ("status", Ada_Quality.Types.Image (Execution.Status));
            String_Member ("tool", To_String (Execution.Tool));
            Boolean_Member ("truncated", Execution.Truncated);
            Close_Container ('}');
         end Emit;
      begin
         Open_Array_Member ("executions");
         for Run of Run_Rows loop
            Ada_Quality.Reporting.Visit_Executions (Item, Run.Id, Emit'Access);
         end loop;
         Close_Container (']');
      end Emit_Executions;

      procedure Emit_Findings is
         procedure Emit (Finding : Ada_Quality.History_Data.Detail_Info) is
         begin
            Open_Object_Element;
            Integer_Member ("assessment_id", Long_Long_Integer (Finding.Run_Id));
            String_Member ("fingerprint", To_String (Finding.Kind));
            Integer_Member ("id", Long_Long_Integer (Finding.Id));
            String_Member ("severity", To_String (Finding.State));
            String_Member ("summary", To_String (Finding.Summary));
            Close_Container ('}');
         end Emit;
      begin
         Open_Array_Member ("findings");
         for Run of Run_Rows loop
            Ada_Quality.Reporting.Visit_Details
              (Item, Run.Id, Ada_Quality.Reporting.Finding_Details, Emit'Access);
         end loop;
         Close_Container (']');
      end Emit_Findings;

      procedure Emit_Measurements is
         procedure Emit (Measurement : Ada_Quality.History_Data.Detail_Info) is
            State : constant String := To_String (Measurement.State);
            Separator : constant Natural := Ada.Strings.Fixed.Index (State, ";");
            Kind : constant String :=
              (if Separator = 0 then State else State (State'First .. Separator - 1));
         begin
            Open_Object_Element;
            Integer_Member ("assessment_id", Long_Long_Integer (Measurement.Run_Id));
            Integer_Member ("id", Long_Long_Integer (Measurement.Id));
            String_Member ("indicator", To_String (Measurement.Kind));
            String_Member ("kind", Kind);
            String_Member ("semantics", State);
            String_Member ("value", To_String (Measurement.Summary));
            Close_Container ('}');
         end Emit;
      begin
         Open_Array_Member ("measurements");
         for Run of Run_Rows loop
            Ada_Quality.Reporting.Visit_Details
              (Item, Run.Id, Ada_Quality.Reporting.Measurement_Details, Emit'Access);
         end loop;
         Close_Container (']');
      end Emit_Measurements;

      procedure Emit_Projects is
      begin
         Open_Array_Member ("projects");
         for Project of Project_Rows loop
            Open_Object_Element;
            Boolean_Member ("enabled", Project.Enabled);
            Integer_Member ("id", Long_Long_Integer (Project.Id));
            String_Member ("path", To_String (Project.Path));
            Boolean_Member ("removed", Project.Removed);
            Tags_Member (To_String (Project.Tags));
            Close_Container ('}');
         end loop;
         Close_Container (']');
      end Emit_Projects;

      procedure Emit_Regressions is
      begin
         Open_Array_Member ("regressions");
         for Project of Project_Rows loop
            declare
               Current_Id : constant Natural := Latest_Selected_Run (Project.Id);
            begin
               if Current_Id > 0 then
                  declare
                     Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
                       Ada_Quality.Reporting.Compare_Project (Item, Project.Id, Current_Id);
                  begin
                     if Comparison.Selection.Baseline_Id = 0 or else
                       Run_Selected (Comparison.Selection.Baseline_Id)
                     then
                        for Change of Comparison.Changes loop
                           Open_Object_Element;
                           String_Member ("after", To_String (Change.After));
                           Integer_Member
                             ("baseline_id", Long_Long_Integer (Comparison.Selection.Baseline_Id));
                           String_Member ("before", To_String (Change.Before));
                           Integer_Member
                             ("current_id", Long_Long_Integer (Comparison.Selection.Current_Id));
                           String_Member ("indicator", Ada_Quality.Types.Image (Change.Indicator));
                           String_Member ("kind", Ada_Quality.History.Image (Change.Kind));
                           Integer_Member ("project_id", Long_Long_Integer (Comparison.Project_Id));
                           Close_Container ('}');
                        end loop;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Close_Container (']');
      end Emit_Regressions;

      procedure Emit_Results is
         procedure Emit (Result : Ada_Quality.History_Data.Detail_Info) is
         begin
            Open_Object_Element;
            Integer_Member ("assessment_id", Long_Long_Integer (Result.Run_Id));
            Integer_Member ("id", Long_Long_Integer (Result.Id));
            String_Member ("indicator", To_String (Result.Kind));
            String_Member ("state", To_String (Result.State));
            String_Member ("summary", To_String (Result.Summary));
            Close_Container ('}');
         end Emit;
      begin
         Open_Array_Member ("results");
         for Run of Run_Rows loop
            Ada_Quality.Reporting.Visit_Details
              (Item, Run.Id, Ada_Quality.Reporting.Result_Details, Emit'Access);
         end loop;
         Close_Container (']');
      end Emit_Results;

      function Project_Selected (Id : Positive) return Boolean is
      begin
         if Project_Id > 0 and then Id /= Project_Id then return False; end if;
         if Project_Tag = "" then return True; end if;
         for Project of All_Projects loop
            if Project.Id = Id then
               return Ada.Strings.Fixed.Index
                 ("," & To_String (Project.Tags) & ",", "," & Project_Tag & ",") > 0;
            end if;
         end loop;
         return False;
      end Project_Selected;
   begin
      for Run of All_Runs loop
         if Project_Selected (Run.Project_Id) and then
           Time_Selected (Run.Started_At)
         then
            for History of All_History loop
               if History.Id = Run.Id then Run_Rows.Append (History); end if;
            end loop;
         end if;
      end loop;
      for Project of All_Projects loop
         if Project_Selected (Project.Id) and then
           ((not Since_Time.Present and then not Until_Time.Present) or else
            Latest_Selected_Run (Project.Id) > 0)
         then
            Project_Rows.Append (Project);
         end if;
      end loop;
      Open_Root;
      Emit_Assessments;
      Emit_Comparisons;
      Emit_Events;
      Emit_Executions;
      Emit_Findings;
      Emit_Measurements;
      Emit_Projects;
      Emit_Regressions;
      Emit_Results;

      Integer_Member ("schema_version", 2);
      Close_Container ('}');
      return To_String (Buffer);
   end Render;
end Ada_Quality.Archive_JSON;
