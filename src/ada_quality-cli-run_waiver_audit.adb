with Ada_Quality.Checks;
with Ada_Quality.Policy;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
function Run_Waiver_Audit (DB_Path, Policy_Path : String) return Natural is
   Session : Ada_Quality.Reporting.Session;
   Profile : constant String := Option ("--profile", "");
   Loaded : constant Ada_Quality.Policy.Load_Result := Ada_Quality.Policy.Load
     (Ada_Quality.Policy.Profile_Path (Policy_Path, Profile));
   Output : Ada.Strings.Unbounded.Unbounded_String;
   Invalid : Natural := 0;
   Expiring : Natural := 0;
   Count : Natural := 0;
   Items : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
   Reports : Ada_Quality.Command_Models.Waiver_Report_Vectors.Vector;
   Max_Invalid : Natural := 0;
   Max_Expiring : Natural := Natural'Last;
   Format : constant String :=
     Selected_Output_Format
       ("text", "text|json", "waiver audit format requires text or json");

   procedure Validate_Request is
   begin
      if Profile /= "" and then not Ada_Quality.Policy.Is_Profile_Name (Profile) then
         raise Usage_Error with "--profile requires letters, digits, underscores, or hyphens";
      elsif not Loaded.Success then
         raise Usage_Error with To_String (Loaded.Error);
      end if;
      begin
         if Option ("--max-invalid", "") /= "" then
            Max_Invalid := Natural'Value (Option ("--max-invalid", ""));
         end if;
         if Option ("--max-expiring", "") /= "" then
            Max_Expiring := Natural'Value (Option ("--max-expiring", ""));
         end if;
      exception
         when Constraint_Error =>
            raise Usage_Error with "--max-invalid and --max-expiring require nonnegative counts";
      end;
   end Validate_Request;

   function Selected_Projects return Ada_Quality.Reporting.Project_Vectors.Vector is
      Selected : Ada_Quality.Reporting.Project_Vectors.Vector;
      Tag : constant String := Option ("--tag", "");
   begin
      if Tag /= "" and then
        not Ada_Quality.Storage.Registry.Is_Tag_Name (Tag)
      then
         raise Usage_Error with "--tag requires lowercase letters, digits, hyphens, or underscores";
      elsif Option ("--project", "") /= "" then
         Selected.Append
           (Ada_Quality.Reporting.Project (Session, Positive_Option ("--project", "project")));
      else
         for Project of Ada_Quality.Reporting.Projects (Session) loop
            if Tag = "" or else Has_Tag (To_String (Project.Tags), Tag) then
               Selected.Append (Project);
            end if;
         end loop;
      end if;
      return Selected;
   end Selected_Projects;

   procedure Record_Item
     (Project_Id : Positive; Item : Ada_Quality.Checks.Waiver_Audit_Item)
   is
   begin
      Count := Count + 1;
      if Item.Status in Ada_Quality.Checks.Waiver_Expired | Ada_Quality.Checks.Waiver_Invalid then
         Invalid := Invalid + 1;
      end if;
      if Item.Expiring then
         Expiring := Expiring + 1;
      end if;
      Append
        (Output, "project" & Positive'Image (Project_Id) & " " &
         Ada_Quality.Checks.Waiver_Status'Image (Item.Status) & " " &
         To_String (Item.Rule) & " target=" & To_String (Item.Target) & " " &
         To_String (Item.Relative_Path) & ":" & Positive'Image (Item.Line) &
         " owner=" & To_String (Item.Owner) & " expires=" & To_String (Item.Expires) &
         (if Item.Expiring then " expiring-within-30-days" else "") & ASCII.LF);
   end Record_Item;

   procedure Audit_Project (Project : Ada_Quality.Reporting.Project_Record) is
      Effective : Ada_Quality.Policy.Load_Result := Loaded;
      Override : constant String := To_String (Project.Path) & "/quality-policy.override.toml";
      Project_Items : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
   begin
      if Project_Tools.Files.File_Exists (Override) then
         Effective := Ada_Quality.Policy.Load_Overlay (Override, Loaded.Value);
         if not Effective.Success then
            raise Usage_Error with To_String (Effective.Error);
         end if;
      end if;
      Project_Items := Ada_Quality.Checks.Audit_Waivers (To_String (Project.Path), Effective.Value);
      Reports.Append
        (Ada_Quality.Command_Models.Waiver_Report'
           (Project.Id, Project.Path, Project_Items));
      Items.Append_Vector (Project_Items);
      for Item of Project_Items loop
         Record_Item (Project.Id, Item);
      end loop;
   end Audit_Project;

   procedure Emit_JSON is
   begin
      Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
      if Has_Flag ("--all") or else Option ("--tag", "") /= "" then
         Emit_Document
           (Ada_Quality.JSON_Administration.Render_Waiver_Batch
              (Reports, Maximum_Invalid => Max_Invalid,
               Maximum_Expiring => Max_Expiring, Invalid_Count => Invalid,
               Expiring_Count => Expiring, Pretty => True));
      else
         Emit_Document
           (Ada_Quality.JSON_Administration.Render_Waivers
              (Items, Maximum_Invalid => Max_Invalid,
               Maximum_Expiring => Max_Expiring, Invalid_Count => Invalid,
               Expiring_Count => Expiring, Pretty => True));
      end if;
   end Emit_JSON;

   procedure Emit_Result is
   begin
      if Format = "json" then
         Emit_JSON;
      else
         Emit_Document (To_String (Output));
      end if;
   end Emit_Result;
begin
   Validate_Request;
   Ada_Quality.Reporting.Open (Session, DB_Path);
   for Project of Selected_Projects loop
      Audit_Project (Project);
   end loop;
   if Count = 0 then Append (Output, "no source waivers found" & ASCII.LF); end if;
   Append
     (Output, "waiver audit:" & Natural'Image (Count - Invalid) & " active," &
      Natural'Image (Invalid) & " invalid or expired" & ASCII.LF);
   Emit_Result;
   return (if Invalid <= Max_Invalid and then Expiring <= Max_Expiring then 0 else 1);
end Run_Waiver_Audit;
