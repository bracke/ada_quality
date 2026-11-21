with Ada_Quality.Policy;

separate (Ada_Quality.CLI)
--  Policy command group kept outside the central CLI dispatcher.
function Run_Policy
  (DB_Path, Policy_Path : String;
   Subcommand : Subcommand_Id) return Natural
is
   Profile : constant String := Option ("--profile", "");
   Selected_Path : constant String := Ada_Quality.Policy.Profile_Path (Policy_Path, Profile);
   Format : constant String := Selected_Output_Format
     ("text", "text|json", "policy format requires text or json");
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

   procedure Run_Profiles is
      Directory : constant String := Ada.Directories.Containing_Directory (Policy_Path);
      Name      : constant String := Ada.Directories.Simple_Name (Policy_Path);
      Dot       : Natural := 0;
      Search    : Ada.Directories.Search_Type;
      Search_Open : Boolean := False;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
      Output    : Ada.Strings.Unbounded.Unbounded_String;
      Profiles  : Text_Vectors.Vector;

      function Less
        (Left, Right : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
        (To_String (Left) < To_String (Right));
      package Sorting is new Text_Vectors.Generic_Sorting ("<" => Less);
   begin
      for Index in reverse Name'Range loop
         if Name (Index) = '.' then Dot := Index; exit; end if;
      end loop;
      if Project_Tools.Files.File_Exists (Policy_Path) then
         Append (Output, "default" & ASCII.LF);
      end if;
      if Dot > Name'First then
         declare
            Stem   : constant String := Name (Name'First .. Dot - 1);
            Suffix : constant String := Name (Dot .. Name'Last);
         begin
            Ada.Directories.Start_Search
              (Search, Directory, Stem & ".*" & Suffix,
               [Ada.Directories.Ordinary_File => True, others => False]);
            Search_Open := True;
            while Ada.Directories.More_Entries (Search) loop
               Ada.Directories.Get_Next_Entry (Search, Dir_Entry);
               declare
                  Candidate : constant String := Ada.Directories.Simple_Name (Dir_Entry);
                  First     : constant Natural := Stem'Length + 2;
                  Last      : constant Natural := Candidate'Length - Suffix'Length;
               begin
                  if First <= Last and then Ada_Quality.Policy.Is_Profile_Name
                    (Candidate (First .. Last))
                  then
                     Profiles.Append (To_Unbounded_String (Candidate (First .. Last)));
                  end if;
               end;
            end loop;
            Ada.Directories.End_Search (Search);
            Search_Open := False;
         end;
      end if;
      Sorting.Sort (Profiles);
      if JSON_Mode then
         declare Values : Ada_Quality.Command_Models.String_Vectors.Vector; begin
            if Project_Tools.Files.File_Exists (Policy_Path) then
               Values.Append (To_Unbounded_String ("default"));
            end if;
            for Item of Profiles loop Values.Append (Item); end loop;
            Emit_Document
              (Ada_Quality.JSON_Administration.Render_String_List
                 ("policy-profiles", "profiles", Values, Pretty => True));
         end;
      else
         for Item of Profiles loop Append (Output, To_String (Item) & ASCII.LF); end loop;
         Emit_Document (To_String (Output));
      end if;
   exception
      when others =>  --  AQ: audited exception boundary
         if Search_Open then Ada.Directories.End_Search (Search); end if;
         raise;
   end Run_Profiles;

   procedure Run_Diff is
      Left_Name  : constant String := Positional (3);
      Right_Name : constant String := Positional (4);
   begin
      if Left_Name = "" or else Right_Name = "" then
         raise Usage_Error with "policy diff requires two profile names (use default for the base policy)";
      end if;
      Require_Profile_Name (Left_Name);
      Require_Profile_Name (Right_Name);
      declare
         Left  : constant Ada_Quality.Policy.Load_Result :=
           Ada_Quality.Policy.Load (Policy_Profile_Path (Left_Name));
         Right : constant Ada_Quality.Policy.Load_Result :=
           Ada_Quality.Policy.Load (Policy_Profile_Path (Right_Name));
      begin
         if not Left.Success then raise Usage_Error with To_String (Left.Error); end if;
         if not Right.Success then raise Usage_Error with To_String (Right.Error); end if;
         if JSON_Mode then
            Emit_Document
              (Ada_Quality.JSON_Administration.Render_Policy_Diff
                 (Left_Name, Right_Name, Left.Value, Right.Value, Pretty => True));
         else
            Emit_Document (Ada_Quality.Policy.Diff (Left.Value, Right.Value));
         end if;
      end;
   end Run_Diff;

   function Run_Loaded return Natural is
      Loaded : Ada_Quality.Policy.Load_Result := Ada_Quality.Policy.Load (Selected_Path);
   begin
      if not Loaded.Success then raise Usage_Error with To_String (Loaded.Error); end if;
      if Subcommand = Policy_Effective then
            declare
               Session : Ada_Quality.Reporting.Session;
               Project_Id : constant Positive := Positive_Option ("--project", "project");
               Overlay_Presence : Ada_Quality.Policy.Key_Presence := (others => False);
               Overlay_Path : Ada.Strings.Unbounded.Unbounded_String;
            begin
               Ada_Quality.Reporting.Open (Session, DB_Path);
               declare
                  Project : constant Ada_Quality.Reporting.Project_Record :=
                    Ada_Quality.Reporting.Project (Session, Project_Id);
                  Overlay : constant String := Project_Tools.Files.Join
                    (To_String (Project.Path), "quality-policy.override.toml");
               begin
                  if Project_Tools.Files.File_Exists (Overlay) then
                     Loaded := Ada_Quality.Policy.Load_Overlay (Overlay, Loaded.Value);
                     if not Loaded.Success then raise Usage_Error with To_String (Loaded.Error); end if;
                     Overlay_Presence := Loaded.Present;
                     Overlay_Path := To_Unbounded_String (Overlay);
                  end if;
               end;
               if JSON_Mode then
                  Emit_Document
                    (Ada_Quality.JSON_Administration.Render_Policy
                       (Loaded.Value,
                        (if Length (Overlay_Path) = 0 then Selected_Path else To_String (Overlay_Path)),
                        Pretty => True));
               elsif Has_Flag ("--explain") then
                  Emit_Document
                    (Ada_Quality.Policy.Explain
                       (Loaded.Value, Overlay_Presence, Selected_Path,
                        (if Length (Overlay_Path) = 0 then Selected_Path else To_String (Overlay_Path))));
               else
                  Emit_Document (Ada_Quality.Policy.Render (Loaded.Value));
               end if;
            end;
      elsif Subcommand = Policy_Validate then
         if JSON_Mode then
            Emit_Document
              (Ada_Quality.JSON_Administration.Render_Command_Result
                 ("policy validate", Ada_Quality.Policy.Fingerprint (Loaded.Value), True, Pretty => True));
         else
            Emit_Document ("valid policy " & Ada_Quality.Policy.Fingerprint (Loaded.Value) & ASCII.LF);
         end if;
      elsif Subcommand = Policy_Show then
         if JSON_Mode then
            Emit_Document
              (Ada_Quality.JSON_Administration.Render_Policy
                 (Loaded.Value, Selected_Path, Pretty => True));
         else
            Emit_Document (Ada_Quality.Policy.Render (Loaded.Value));
         end if;
      else
         raise Usage_Error with
           "policy requires init, validate, show, profiles, diff, impact, or effective";
      end if;
      return 0;
   end Run_Loaded;

   function Dispatch return Natural is
   begin
      if Subcommand = No_Subcommand then
         raise Usage_Error with "policy operation is required";
      end if;
      if Profile /= "" and then not Ada_Quality.Policy.Is_Profile_Name (Profile) then
         raise Usage_Error with "--profile requires letters, digits, underscores, or hyphens";
      elsif Subcommand = Policy_Init then
         if Project_Tools.Files.Exists (Selected_Path) then
            raise Usage_Error with "policy file already exists: " & Selected_Path;
         end if;
         Project_Tools.Files.Write_Text_File
           (Selected_Path, Ada_Quality.Policy.Render (Ada_Quality.Policy.Default));
         if JSON_Mode then
            Emit_Document
              (Ada_Quality.JSON_Administration.Render_Command_Result
                 ("policy init", "created " & Selected_Path, True, Pretty => True));
         else
            Emit_Document ("created " & Selected_Path & ASCII.LF);
         end if;
         return 0;
      elsif Subcommand = Policy_Profiles then
         Run_Profiles;
         return 0;
      elsif Subcommand = Policy_Diff then
         Run_Diff;
         return 0;
      elsif Subcommand = Policy_Impact then
         return Run_Policy_Impact (DB_Path, Policy_Path);
      end if;
      return Run_Loaded;
   end Dispatch;
begin
   return Dispatch;
end Run_Policy;
