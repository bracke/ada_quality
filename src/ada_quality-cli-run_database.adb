with Ada_Quality.Artifact_Signing;
with Ada_Quality.Artifact_Staging;
with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Assessments;
with Ada_Quality.Storage.Integrity;
with Ada_Quality.Storage.Transfer;
with Ada_Quality.Temporary_Directories;

separate (Ada_Quality.CLI)
function Run_Database
  (DB_Path : String; Operation : Subcommand_Id) return Natural is
   Store : Ada_Quality.Storage.Store;
   Verification_Stage : Ada_Quality.Temporary_Directories.Temporary_Directory;
   Format : constant String := Selected_Output_Format
     ("text", "text|json", "database format requires text or json");
   JSON_Mode : constant Boolean := Format = "json";
   Trust_Store : constant String := Option ("--trust-store", ".ada-quality-trust");

   procedure Result (Command, Detail : String) is
   begin
      if JSON_Mode then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Emit_Document
           (Ada_Quality.JSON_Administration.Render_Command_Result
              (Command, Detail, Success => True, Pretty => True));
      else
         Emit_Document (Detail & ASCII.LF);
      end if;
   end Result;

   procedure Open_Store (Create : Boolean := True) is
   begin
      Ada_Quality.Storage.Open (Store, DB_Path, Create);
   end Open_Store;

   procedure Sign_Created_Artifact (Artifact : String; Backup : Boolean) is
      Key : constant String := Option ("--sign-key", "");
   begin
      if Key /= "" then
         begin
            Ada_Quality.Artifact_Signing.Sign (Artifact, Key);
         exception
            when others =>  --  AQ: audited exception boundary
               if Backup then
                  Project_Tools.Files.Delete_Tree (Artifact);
               else
                  Project_Tools.Files.Delete_File_If_Present (Artifact);
               end if;
               raise;
         end;
      end if;
   end Sign_Created_Artifact;

   procedure Verify_If_Required (Artifact : String) is
      Key : constant String := Option ("--public-key", "");
   begin
      if Key /= "" and then Option ("--trust-store", "") /= "" then
         raise Usage_Error with "--public-key and --trust-store are mutually exclusive";
      elsif Key /= "" then
         Ada_Quality.Artifact_Signing.Verify (Artifact, Key);
      elsif Option ("--trust-store", "") /= "" then
         Ada_Quality.Artifact_Signing.Verify_Trusted (Artifact, Trust_Store);
      end if;
   end Verify_If_Required;

   function Verified_Copy (Artifact : String) return String is
   begin
      if Option ("--public-key", "") = "" and then Option ("--trust-store", "") = "" then
         return Artifact;
      end if;
      Ada_Quality.Temporary_Directories.Create
        (Verification_Stage, "ada-quality-verified-artifact");
      declare
         Staged : constant String :=
           Ada_Quality.Temporary_Directories.Child (Verification_Stage, "artifact");
      begin
         Ada_Quality.Artifact_Staging.Copy (Artifact, Staged);
         Verify_If_Required (Staged);
         return Staged;
      end;
   end Verified_Copy;

   function Run_Trust return Natural is
      Action : constant String := Positional (3);
   begin
      if Action = "add" then
         if Positional (4) = "" then raise Usage_Error with "database trust add requires a public key"; end if;
         Result
           ("database trust add",
            "trusted " & Ada_Quality.Artifact_Signing.Add_Trusted_Key (Trust_Store, Positional (4)));
      elsif Action = "remove" then
         if Positional (4) = "" then raise Usage_Error with "database trust remove requires a key ID"; end if;
         Ada_Quality.Artifact_Signing.Remove_Trusted_Key (Trust_Store, Positional (4));
         Result ("database trust remove", "removed " & Positional (4));
      elsif Action = "list" then
         declare
            Keys : constant Ada_Quality.Artifact_Signing.Trusted_Key_Vectors.Vector :=
              Ada_Quality.Artifact_Signing.Trusted_Keys (Trust_Store);
         begin
            if JSON_Mode then
               Emit_Document
                 (Ada_Quality.JSON_Administration.Render_Trusted_Keys
                    (Keys, Pretty => True));
            else
               declare Output : Ada.Strings.Unbounded.Unbounded_String; begin
                  for Key of Keys loop
                     Append (Output, To_String (Key.Id) & " " & To_String (Key.Path) & ASCII.LF);
                  end loop;
                  Emit_Document (To_String (Output));
               end;
            end if;
         end;
      else
         raise Usage_Error with "database trust requires add, list, or remove";
      end if;
      return 0;
   end Run_Trust;

   function Run_Merge return Natural is
      Report    : Ada_Quality.Storage.Merge_Report;
      Conflicts : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Sources   : Ada_Quality.Storage.Source_Vectors.Vector;
      Index     : Positive := 3;
   begin
      if Positional (3) = "" then raise Usage_Error with "database merge requires a source path"; end if;
      while Positional (Index) /= "" loop
         if Ada.Directories.Exists (Positional (Index)) and then Ada.Directories.Exists (DB_Path) and then
           Ada.Directories.Full_Name (Positional (Index)) = Ada.Directories.Full_Name (DB_Path)
         then
            raise Usage_Error with "database cannot be merged into itself";
         end if;
         Sources.Append (To_Unbounded_String (Positional (Index)));
         Index := Index + 1;
      end loop;
      Open_Store (False);
      Ada_Quality.Storage.Integrity.Check (Store);
      Ada_Quality.Storage.Transfer.Merge
        (Store, Sources, Has_Flag ("--dry-run"), Report);
      for Conflict of Report.Conflicts loop
         Conflicts.Append
           (Ada_Quality.Command_Models.Diagnostic_Item'
              (Name => Conflict.Name, Passed => False, Detail => Conflict.Detail));
      end loop;
      if JSON_Mode then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Emit_Document
           (Ada_Quality.JSON_Administration.Render_Merge
              (Sources, Has_Flag ("--dry-run"), Report.Added_Projects,
               Report.Added_Assessments, Report.Reused_Assessments, Report.Added_Aliases,
               Conflicts, Pretty => True));
      else
         Emit_Document
           ((if Has_Flag ("--dry-run") then "merge preview:" else "merged") &
            Natural'Image (Report.Added_Projects) & " project(s)," &
            Natural'Image (Report.Added_Assessments) & " assessment(s)," &
            Natural'Image (Report.Reused_Assessments) & " reused," &
            Natural'Image (Report.Added_Aliases) & " alias(es)," &
            Natural'Image (Natural (Report.Conflicts.Length)) & " conflict(s)" & ASCII.LF);
      end if;
      return (if Report.Conflicts.Is_Empty then 0 else 1);
   end Run_Merge;

   function Run_Archive return Natural is
      Before  : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--before");
      Keep    : Natural := 10;
      Removed : Natural;
   begin
      if Positional (3) = "" and then not Has_Flag ("--dry-run") then
         raise Usage_Error with "database archive requires a destination path";
      elsif not Before.Present then
         raise Usage_Error with "database archive requires --before YYYY-MM-DDTHH:MM:SSZ";
      end if;
      if Option ("--keep", "") /= "" then
         begin
            Keep := Natural'Value (Option ("--keep", ""));
         exception
            when Constraint_Error => raise Usage_Error with "--keep requires a nonnegative count";
         end;
      end if;
      Open_Store (False);
      Ada_Quality.Storage.Integrity.Check (Store);
      if Has_Flag ("--dry-run") then
         declare
            Candidates : constant Ada_Quality.Storage.History_Vectors.Vector :=
              Ada_Quality.Storage.Transfer.Retention_Candidates
                (Store, Before.Value, Keep);
            Output : Ada.Strings.Unbounded.Unbounded_String;
         begin
            if JSON_Mode then
               Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
               Emit_Document
                 (Ada_Quality.JSON_Administration.Render_Retention
                    (Candidates, Option ("--before", ""), Keep, Pretty => True));
            else
               Append
                 (Output, "retention preview:" & Natural'Image (Natural (Candidates.Length)) &
                  " assessment(s) would be removed" & ASCII.LF);
               for Run of Candidates loop
                  Append
                    (Output, "assessment" & Positive'Image (Run.Id) & " project" &
                     Positive'Image (Run.Project_Id) & " " & To_String (Run.Status) & ASCII.LF);
               end loop;
               Emit_Document (To_String (Output));
            end if;
         end;
      else
         Ada_Quality.Storage.Transfer.Archive_And_Prune
           (Store, Positional (3), Before.Value, Keep, Removed);
         Ada_Quality.Storage.Transfer.Compact (Store);
         Ada_Quality.Storage.Integrity.Check (Store);
         Result
           ("database archive",
            "archived database and removed" & Natural'Image (Removed) & " assessment(s)");
      end if;
      return 0;
   end Run_Archive;

   function Run_Signature_Operation return Natural is
   begin
      if Operation = Database_Keygen then
         if Positional (3) = "" or else Positional (4) = "" then
            raise Usage_Error with "database keygen requires private and public key paths";
         end if;
         Ada_Quality.Artifact_Signing.Generate_Keypair (Positional (3), Positional (4));
         Result ("database keygen", "generated Ed25519 keypair");
      elsif Operation = Database_Verify then
         if Positional (3) = "" or else
           (Option ("--public-key", "") = "" and then Option ("--trust-store", "") = "")
         then
            raise Usage_Error with "database verify requires an artifact and --public-key or --trust-store";
         end if;
         declare
            Verified : constant String := Verified_Copy (Positional (3));
            Info : Ada_Quality.Artifact_Signing.Signature_Info :=
              Ada_Quality.Artifact_Signing.Inspect (Verified);
         begin
            --  Report the caller-visible path, but retain metadata read from
            --  the exact private snapshot that was verified.
            Info.Path := To_Unbounded_String
              (Ada_Quality.Artifact_Signing.Signature_Path (Positional (3)));
            if JSON_Mode then
               Emit_Document
                 (Ada_Quality.JSON_Administration.Render_Signature
                    (Info, True, Pretty => True));
            else
               Emit_Document ("artifact signature verified" & ASCII.LF);
            end if;
         end;
      elsif Operation = Database_Inspect then
         if Positional (3) = "" then
            raise Usage_Error with "database inspect requires an artifact";
         end if;
         declare
            Info : constant Ada_Quality.Artifact_Signing.Signature_Info :=
              Ada_Quality.Artifact_Signing.Inspect (Positional (3));
         begin
            if JSON_Mode then
               Emit_Document
                 (Ada_Quality.JSON_Administration.Render_Signature
                    (Info, False, Pretty => True));
            else
               Emit_Document
                 ("kind=" & To_String (Info.Kind) & ASCII.LF &
                  "algorithm=" & To_String (Info.Algorithm) & ASCII.LF &
                  "key_id=" & To_String (Info.Key) & ASCII.LF &
                  "digest=" & To_String (Info.Digest) & ASCII.LF);
            end if;
         end;
      else
         return Run_Trust;
      end if;
      return 0;
   end Run_Signature_Operation;

   function Run_Store_Operation return Natural is
   begin
      if Operation = Database_Init then
         Open_Store;
         Ada_Quality.Storage.Integrity.Check (Store);
         Result ("database init", "initialized " & DB_Path);
      elsif Operation = Database_Check then
         Open_Store (False);
         Ada_Quality.Storage.Integrity.Check (Store);
         Result ("database check", "database integrity check passed");
      elsif Operation = Database_Recover then
         Open_Store (False);
         declare
            Count : Natural;
         begin
            Ada_Quality.Storage.Assessments.Recover (Store, Count);
            Result ("database recover", "recovered" & Natural'Image (Count) & " assessment(s)");
         end;
      elsif Operation = Database_Compact then
         Open_Store (False);
         Ada_Quality.Storage.Integrity.Check (Store);
         Ada_Quality.Storage.Transfer.Compact (Store);
         Ada_Quality.Storage.Integrity.Check (Store);
         Result ("database compact", "database compacted");
      else
         declare
            Session : Ada_Quality.Reporting.Session;
         begin
            Ada_Quality.Reporting.Open (Session, DB_Path);
            declare
               Stats : constant Ada_Quality.Reporting.Snapshot_Statistics :=
                 Ada_Quality.Reporting.Statistics (Session);
            begin
               if JSON_Mode then
                  Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
                  Emit_Document
                    (Ada_Quality.JSON_Reports.Render_Statistics
                       (Stats, Pretty => True));
               else
                  Emit_Document
                    ("projects" & Natural'Image (Stats.Projects) & ASCII.LF &
                     "assessments" & Natural'Image (Stats.Assessments) & ASCII.LF &
                     "results" & Natural'Image (Stats.Results) & ASCII.LF &
                     "measurements" & Natural'Image (Stats.Measurements) & ASCII.LF &
                     "findings" & Natural'Image (Stats.Findings) & ASCII.LF &
                     "executions" & Natural'Image (Stats.Executions) & ASCII.LF &
                     "events" & Natural'Image (Stats.Events) & ASCII.LF &
                     "total rows" & Natural'Image (Stats.Total_Rows) & " /" &
                       Positive'Image (Stats.Row_Limit) & ASCII.LF &
                     "text bytes" & Long_Long_Integer'Image (Stats.Text_Bytes) & " /" &
                       Positive'Image (Stats.Text_Limit) & ASCII.LF);
               end if;
            end;
         end;
      end if;
      return 0;
   end Run_Store_Operation;

   function Run_Transfer_Operation return Natural is
   begin
      if Operation in Database_Backup | Database_Export then
         if Positional (3) = "" then
            raise Usage_Error with
              "database " & Image (Operation) & " requires a destination path";
         end if;
         Open_Store (False);
         Ada_Quality.Storage.Integrity.Check (Store);
         if Operation = Database_Backup then
            Ada_Quality.Storage.Transfer.Backup (Store, Positional (3));
            Sign_Created_Artifact (Positional (3), Backup => True);
         else
            Ada_Quality.Storage.Transfer.Export (Store, Positional (3));
            Sign_Created_Artifact (Positional (3), Backup => False);
         end if;
         Result
           ("database " & Image (Operation),
            Image (Operation) & " created at " & Positional (3));
      elsif Operation = Database_Restore then
         if Positional (3) = "" then
            raise Usage_Error with "database restore requires a source path";
         end if;
         Ada_Quality.Storage.Transfer.Restore
           (Verified_Copy (Positional (3)), DB_Path);
         Open_Store (False);
         Ada_Quality.Storage.Integrity.Check (Store);
         Result ("database restore", "restored " & DB_Path);
      else
         if Positional (3) = "" then
            raise Usage_Error with "database import requires a source path";
         end if;
         Ada_Quality.Storage.Transfer.Import
           (Verified_Copy (Positional (3)), DB_Path);
         Open_Store (False);
         Ada_Quality.Storage.Integrity.Check (Store);
         Result ("database import", "imported " & DB_Path);
      end if;
      return 0;
   end Run_Transfer_Operation;

   procedure Validate_Request is
   begin
      if Operation = No_Subcommand then
         raise Usage_Error with "database operation is required";
      elsif Option ("--sign-key", "") /= "" and then
        Operation not in Database_Backup | Database_Export
      then
         raise Usage_Error with "--sign-key is supported only by database backup and export";
      elsif Option ("--public-key", "") /= "" and then
        Operation not in Database_Verify | Database_Restore | Database_Import
      then
         raise Usage_Error with "--public-key is supported only by database verify, restore, and import";
      elsif Option ("--trust-store", "") /= "" and then
        Operation not in Database_Verify | Database_Restore | Database_Import |
          Database_Trust
      then
         raise Usage_Error with "--trust-store is supported only by database verify, restore, import, and trust";
      end if;
   end Validate_Request;

   function Dispatch return Natural is
   begin
      Validate_Request;
      if Operation in Database_Keygen | Database_Verify | Database_Inspect |
        Database_Trust
      then
         return Run_Signature_Operation;
      elsif Operation in Database_Init | Database_Check | Database_Recover |
        Database_Compact | Database_Stats
      then
         return Run_Store_Operation;
      elsif Operation in Database_Backup | Database_Export | Database_Restore |
        Database_Import
      then
         return Run_Transfer_Operation;
      elsif Operation = Database_Merge then
         return Run_Merge;
      elsif Operation = Database_Archive then
         return Run_Archive;
      else
         raise Usage_Error with
           "database requires init, check, recover, compact, stats, keygen, verify, inspect, trust, backup," &
           " export, import, restore, merge, or archive";
      end if;
   end Dispatch;
begin
   return Dispatch;
end Run_Database;
