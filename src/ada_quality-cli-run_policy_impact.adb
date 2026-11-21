with Ada_Quality.Policy;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
function Run_Policy_Impact (DB_Path, Policy_Path : String) return Natural is
   Format : constant String := Selected_Output_Format
     ("text", "text|json", "policy impact format requires text or json");
   JSON_Mode : constant Boolean := Format = "json";

   function Policy_Profile_Path (Name : String) return String is
     (if Name = "default" then Policy_Path else Ada_Quality.Policy.Profile_Path (Policy_Path, Name));

   procedure Require_Profile_Name (Name : String) is
   begin
      if Name /= "default" and then not Ada_Quality.Policy.Is_Profile_Name (Name) then
         raise Usage_Error with
           "policy profile names contain only letters, digits, underscores, or hyphens";
      end if;
   end Require_Profile_Name;

   procedure Add_Policy_Change
     (Keys, Indicators : in out Ada_Quality.Command_Models.String_Vectors.Vector;
      Key, Names : String)
   is
      Start : Positive := Names'First;
      Stop  : Natural;
   begin
      Keys.Append (To_Unbounded_String (Key));
      while Start <= Names'Last loop
         Stop := Ada.Strings.Fixed.Index (Names, ",", From => Start);
         if Stop = 0 then Stop := Names'Last + 1; end if;
         declare
            Name : constant Ada.Strings.Unbounded.Unbounded_String :=
              To_Unbounded_String (Names (Start .. Stop - 1));
            Found : Boolean := False;
         begin
            for Existing of Indicators loop
               if Existing = Name then Found := True; exit; end if;
            end loop;
            if not Found then Indicators.Append (New_Item => Name); end if;
         end;
         Start := Stop + 1;
      end loop;
   end Add_Policy_Change;

   procedure Changed_Policy_Keys
     (Before, After : Ada_Quality.Policy.Quality_Policy;
      Keys, Indicators : in out Ada_Quality.Command_Models.String_Vectors.Vector)
   is
   begin
      for Key in Ada_Quality.Policy.Policy_Key loop
         if Ada_Quality.Policy.Changed (Before, After, Key) then
            Add_Policy_Change
              (Keys, Indicators, Ada_Quality.Policy.Name (Key),
               Ada_Quality.Policy.Affected_Indicators (Key));
         end if;
      end loop;
   end Changed_Policy_Keys;

   procedure Collect_Project_Impact
     (Project : Ada_Quality.Reporting.Project_Record;
      Left, Right : Ada_Quality.Policy.Load_Result;
      Impacts : in out Ada_Quality.Command_Models.Policy_Impact_Vectors.Vector;
      Text_Output : in out Ada.Strings.Unbounded.Unbounded_String)
   is
      Before  : Ada_Quality.Policy.Load_Result := Left;
      After   : Ada_Quality.Policy.Load_Result := Right;
      Overlay : constant String := Project_Tools.Files.Join
        (To_String (Project.Path), "quality-policy.override.toml");
      Keys, Indicators : Ada_Quality.Command_Models.String_Vectors.Vector;
   begin
      if Project_Tools.Files.File_Exists (Overlay) then
         Before := Ada_Quality.Policy.Load_Overlay (Overlay, Left.Value);
         After := Ada_Quality.Policy.Load_Overlay (Overlay, Right.Value);
         if not Before.Success then raise Usage_Error with To_String (Before.Error); end if;
         if not After.Success then raise Usage_Error with To_String (After.Error); end if;
      end if;
      Changed_Policy_Keys (Before.Value, After.Value, Keys, Indicators);
      if Keys.Is_Empty then return; end if;
      Impacts.Append
        (Ada_Quality.Command_Models.Policy_Impact_Item'
           (Project.Id, Project.Path,
            To_Unbounded_String (Ada_Quality.Policy.Fingerprint (Before.Value)),
            To_Unbounded_String (Ada_Quality.Policy.Fingerprint (After.Value)),
            Keys, Indicators));
      Append
        (Text_Output, "project" & Positive'Image (Project.Id) & ":" &
         Ada.Containers.Count_Type'Image (Keys.Length) & " policy key(s) affect" &
         Ada.Containers.Count_Type'Image (Indicators.Length) & " indicator(s)" & ASCII.LF);
   end Collect_Project_Impact;

   Left_Name      : constant String := Positional (3);
   Right_Name     : constant String := Positional (4);
   Session        : Ada_Quality.Reporting.Session;
   Impacts        : Ada_Quality.Command_Models.Policy_Impact_Vectors.Vector;
   Text_Output    : Ada.Strings.Unbounded.Unbounded_String;
   Project_Filter : Natural := 0;
   function Dispatch return Natural is
   begin
      if Left_Name = "" or else Right_Name = "" then
         raise Usage_Error with "policy impact requires two profile names";
      end if;
      Require_Profile_Name (Left_Name);
      Require_Profile_Name (Right_Name);
      if Option ("--tag", "") /= "" and then
        not Ada_Quality.Storage.Registry.Is_Tag_Name (Option ("--tag", ""))
      then
         raise Usage_Error with "--tag requires lowercase letters, digits, hyphens, or underscores";
      end if;
      declare
         Left  : constant Ada_Quality.Policy.Load_Result :=
           Ada_Quality.Policy.Load (Policy_Profile_Path (Left_Name));
         Right : constant Ada_Quality.Policy.Load_Result :=
           Ada_Quality.Policy.Load (Policy_Profile_Path (Right_Name));
      begin
         if not Left.Success then raise Usage_Error with To_String (Left.Error); end if;
         if not Right.Success then raise Usage_Error with To_String (Right.Error); end if;
         Ada_Quality.Reporting.Open (Session, DB_Path);
         if Option ("--project", "") /= "" then
            Project_Filter := Positive_Option ("--project", "project");
            declare
               Selected : constant Ada_Quality.Reporting.Project_Record :=
                 Ada_Quality.Reporting.Project (Session, Positive (Project_Filter));
               pragma Unreferenced (Selected);
            begin
               null;
            end;
         end if;
         for Project of Ada_Quality.Reporting.Projects (Session) loop
            if (Project_Filter = 0 or else Project.Id = Project_Filter) and then
              (Option ("--tag", "") = "" or else
               Has_Tag (To_String (Project.Tags), Option ("--tag", "")))
            then
               Collect_Project_Impact (Project, Left, Right, Impacts, Text_Output);
            end if;
         end loop;
      end;
      if JSON_Mode then
         Emit_Document
           (Ada_Quality.JSON_Administration.Render_Policy_Impact
              (Left_Name, Right_Name, Impacts, Pretty => True));
      else
         if Impacts.Is_Empty then Append (Text_Output, "no effective policy changes" & ASCII.LF); end if;
         Emit_Document (To_String (Text_Output));
      end if;
      return 0;
   end Dispatch;
begin
   return Dispatch;
end Run_Policy_Impact;
