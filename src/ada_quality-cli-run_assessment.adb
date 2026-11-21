with Ada_Quality.CI_Formats;
with Ada_Quality.HTML;
with Ada_Quality.JSON_Assessments;
with Ada_Quality.Storage.Assessments;

separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=run_assessment owner=aq expires=2027-11-21 justification=assessment-command-router
function Run_Assessment
  (Store : in out Ada_Quality.Storage.Store;
   DB_Path : String;
   Subcommand : Subcommand_Id) return Natural is
   type Alias_List_Request is record
      Assessment : Ada.Strings.Unbounded.Unbounded_String;
      Page       : Ada_Quality.Pagination.Page_Request;
      Format     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Parse_Alias_List_Request return Alias_List_Request is
     ((Assessment => To_Unbounded_String (Positional (3)),
       Page       => Requested_Page,
       Format     => To_Unbounded_String
         (Selected_Output_Format
            ("text", "text|json",
             "assessment aliases format requires text or json"))));

   package Alias_Pages is new Ada_Quality.Pagination.Stream_Pages
     (Ada_Quality.Reporting.Alias_Vectors);
begin
   if Subcommand = Assessment_Diff then
      declare
         Session     : Ada_Quality.Reporting.Session;
         Baseline_Id : Positive;
         Current_Id  : Positive;
         Format      : constant String := Selected_Output_Format
           ("text", "text|json", "assessment diff format requires text or json");
         Comparison  : Ada_Quality.Reporting.Project_Comparison;
      begin
         if Positional (3) = "" or else Positional (4) = "" then
            raise Usage_Error with "assessment diff requires baseline and current references";
         end if;
         Ada_Quality.Reporting.Open (Session, DB_Path);
         Baseline_Id := Ada_Quality.Reporting.Resolve_Assessment (Session, Positional (3));
         Current_Id := Ada_Quality.Reporting.Resolve_Assessment (Session, Positional (4));
         if Baseline_Id >= Current_Id then
            raise Usage_Error with "baseline assessment must precede current assessment";
         end if;
         Comparison := Ada_Quality.Reporting.Compare_Assessments
           (Session, Baseline_Id, Current_Id);
         if Format = "json" then
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
            Emit_Document
              (Ada_Quality.JSON_Assessments.Render_Comparison
                 (Comparison, Pretty => True));
         else
            Emit_Document (Comparison_Text (Comparison));
         end if;
      end;
   elsif Subcommand = Assessment_Show then
      declare
         Session : Ada_Quality.Reporting.Session;
         Value   : Assessment;
         Run_Id  : Positive;
         Format  : constant String := Selected_Output_Format
           ("text", "text|json|sarif|junit|html",
            "assessment format requires text, json, sarif, junit, or html");
      begin
         if Format /= "text" then
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         end if;
         Ada_Quality.Reporting.Open (Session, DB_Path);
         if Positional (3) = "" then
            raise Usage_Error with "assessment show requires an assessment reference";
         end if;
         Run_Id := Ada_Quality.Reporting.Resolve_Assessment (Session, Positional (3));
         Value := Stored_Assessment (Session, Run_Id);
         if Format = "json" then
            Emit_Document
              (Ada_Quality.JSON_Assessments.Render (Value, Pretty => True));
         elsif Format = "sarif" then
            Emit_Document (Ada_Quality.CI_Formats.Render_SARIF (Value, Pretty => True));
         elsif Format = "junit" then
            Emit_Document (Ada_Quality.CI_Formats.Render_JUnit (Value));
         elsif Format = "html" then
            Emit_Document (Ada_Quality.HTML.Render_Assessment (Value));
         else
            Emit_Document (Assessment_Text (Value));
         end if;
      end;
   elsif Subcommand = Assessment_Alias then
      if Positional (3) = "" or else Positional (4) = "" then
         raise Usage_Error with "assessment alias requires a name and numeric assessment ID";
      end if;
      declare
         Run_Id : Positive;
      begin
         begin
            Run_Id := Positive'Value (Positional (4));
         exception
            when Constraint_Error =>
               raise Usage_Error with "assessment alias requires a numeric assessment ID";
         end;
         Ada_Quality.Storage.Assessments.Add_Alias
           (Store, Run_Id, Positional (3));
         Ada.Text_IO.Put_Line ("aliased " & Positional (3) & " to assessment" & Positive'Image (Run_Id));
      end;
   elsif Subcommand = Assessment_Aliases then
      declare
         Session : Ada_Quality.Reporting.Session;
         Run_Id  : Natural := 0;
         Request : constant Alias_List_Request :=
           Parse_Alias_List_Request;
      begin
         Ada_Quality.Reporting.Open (Session, DB_Path);
         if Length (Request.Assessment) > 0 then
            Run_Id := Ada_Quality.Reporting.Resolve_Assessment
              (Session, To_String (Request.Assessment));
         end if;
         declare
            All_Aliases : constant Ada_Quality.Reporting.Alias_Vectors.Vector :=
              Ada_Quality.Reporting.Aliases (Session, Run_Id);
            Aliases : Ada_Quality.Reporting.Alias_Vectors.Vector;
            Snapshot : constant Natural := Cursor_Snapshot (Alias_Snapshot (Session));
            Binding : constant Natural := Query_Binding
              ("assessment-aliases|run=" & Natural'Image (Run_Id));
            Total : Natural := 0;
         begin
            Require_Query_Binding (Binding);
            for Item of All_Aliases loop
               if Item.Event_Id <= Snapshot then
                  Alias_Pages.Consider
                    (Aliases, Item, Total, Request.Page);
               end if;
            end loop;
            if To_String (Request.Format) = "json" then
               Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
               Emit_Document
                 (Ada_Quality.JSON_Assessments.Render_Aliases
                    (Aliases, Page_Metadata
                       (Total, Request.Page.Offset, Natural (Aliases.Length),
                        Request.Page.Limit, Snapshot, 0, 0, Binding),
                     Pretty => True));
            else
               declare Output : Ada.Strings.Unbounded.Unbounded_String; begin
                  for Item of Aliases loop
                     Append
                       (Output, To_String (Item.Name) & " assessment" &
                        Positive'Image (Item.Run_Id) & ASCII.LF);
                  end loop;
                  Emit_Document (To_String (Output));
               end;
            end if;
         end;
      end;
   else
      raise Usage_Error with "assessment requires show, diff, alias, or aliases";
   end if;
   return 0;
end Run_Assessment;
