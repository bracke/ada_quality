with Ada_Quality.Artifact_Signing;
with Ada_Quality.Storage.Integrity;

separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=run_request owner=aq expires=2027-11-21 justification=metadata-validated-command-router
function Run_Request return Natural is
   Command     : constant String := Positional (1);
   Subcommand  : constant String := Positional (2);
   DB_Path     : constant String := Option ("--database", Default_Database);
   Policy_Path : constant String := Option ("--policy", Default_Policy);
   Selected_Command : constant Ada_Quality.CLI_Metadata.Command_Id :=
     Ada_Quality.CLI_Metadata.Identify (Command);
   Selected_Subcommand : constant Ada_Quality.CLI_Metadata.Subcommand_Id :=
     (if Ada_Quality.CLI_Metadata.Subcommand_Count (Command) = 0
      then Ada_Quality.CLI_Metadata.No_Subcommand
      else Ada_Quality.CLI_Metadata.Identify_Subcommand
        (Selected_Command, Subcommand));
   Store       : Ada_Quality.Storage.Store;

   procedure Open_Store (Create : Boolean := True) is
   begin
      Ada_Quality.Storage.Open (Store, DB_Path, Create);
   end Open_Store;

begin
   if Argument_Count = 0 then
      Help;
      return 0;
   elsif Command in "--help" | "-h" then
      if Argument_Count /= 1 then
         raise Usage_Error with "help does not accept arguments";
      end if;
      Help;
      return 0;
   elsif Command = "--version" then
      if Argument_Count /= 1 then
         raise Usage_Error with "version does not accept arguments";
      end if;
      Ada.Text_IO.Put_Line (Ada_Quality.Version);
      return 0;
   end if;

   if Selected_Command = Ada_Quality.CLI_Metadata.Unknown_Command then
      raise Usage_Error with "unknown command: " & Command;
   elsif Ada_Quality.CLI_Metadata.Subcommand_Count (Command) > 0 and then
     Subcommand /= "" and then
     Selected_Subcommand = Ada_Quality.CLI_Metadata.Unknown_Subcommand
   then
      raise Usage_Error with "unknown " & Command & " subcommand: " & Subcommand;
   end if;

   Validate_Options (Selected_Command, Selected_Subcommand);

   if Option ("--color", "") = "never" or else
     (for some J in 1 .. Argument_Count => Argument (J) = "--no-color")
   then
      Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
   elsif Option ("--color", "") = "always" then
      Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Always);
   elsif Option ("--color", "") = "auto" then
      Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Auto);
   end if;

   if Ada_Quality.CLI_Metadata.Requires_Store
     (Selected_Command, Selected_Subcommand)
   then
      if Selected_Command = Ada_Quality.CLI_Metadata.Check_Command and then Has_Flag ("--dry-run") then
         declare Snapshot : Ada_Quality.Reporting.Session; begin
            --  Reject an old schema read-only instead of allowing Open_Store to migrate it during a plan.
            Ada_Quality.Reporting.Open (Snapshot, DB_Path);
         end;
      end if;
      Open_Store;
      Ada_Quality.Storage.Integrity.Check (Store);
   end if;
   case Selected_Command is
      when Ada_Quality.CLI_Metadata.Project_Command =>
         return Run_Project (Store, DB_Path, Selected_Subcommand);
      when Ada_Quality.CLI_Metadata.Assessment_Command =>
         return Run_Assessment (Store, DB_Path, Selected_Subcommand);
      when Ada_Quality.CLI_Metadata.Check_Command =>
         return Run_Check (Store, Policy_Path);
      when Ada_Quality.CLI_Metadata.Scan_Command =>
         return Run_Scan (DB_Path, Policy_Path);
      when Ada_Quality.CLI_Metadata.History_Command =>
         return Run_History (DB_Path);
      when Ada_Quality.CLI_Metadata.Status_Command =>
         return Run_Status (DB_Path);
      when Ada_Quality.CLI_Metadata.Findings_Command =>
         Print_Findings (DB_Path);
         return 0;
      when Ada_Quality.CLI_Metadata.Regressions_Command =>
         return Run_Regressions (DB_Path);
      when Ada_Quality.CLI_Metadata.Trend_Command =>
         return Run_Trend (DB_Path);
      when Ada_Quality.CLI_Metadata.Explain_Command =>
         return Run_Explain (Subcommand);
      when Ada_Quality.CLI_Metadata.Indicator_Command =>
         return Run_Indicator_List;
      when Ada_Quality.CLI_Metadata.Report_Command =>
         return Run_Report (DB_Path);
      when Ada_Quality.CLI_Metadata.Policy_Command =>
         return Run_Policy (DB_Path, Policy_Path, Selected_Subcommand);
      when Ada_Quality.CLI_Metadata.Database_Command =>
         return Run_Database (DB_Path, Selected_Subcommand);
      when Ada_Quality.CLI_Metadata.Doctor_Command =>
         return Run_Doctor (DB_Path, Policy_Path);
      when Ada_Quality.CLI_Metadata.Waiver_Command =>
         return Run_Waiver_Audit (DB_Path, Policy_Path);
      when Ada_Quality.CLI_Metadata.Completion_Command =>
         return Run_Completion (Selected_Subcommand);
      when Ada_Quality.CLI_Metadata.Help_Command =>
         Help;
         return 0;
      when Ada_Quality.CLI_Metadata.Version_Command =>
         Ada.Text_IO.Put_Line (Ada_Quality.Version);
         return 0;
      when Ada_Quality.CLI_Metadata.Unknown_Command =>
         raise Program_Error with "validated command has no dispatch target";
   end case;
exception
   when E : Ada_Quality.Artifact_Signing.Signing_Error =>
      Emit_Error ("signing_error", Ada.Exceptions.Exception_Message (E), 4);
      return 4;
   when E : Ada_Quality.Storage.Storage_Error =>
      Emit_Error ("database_error", Ada.Exceptions.Exception_Message (E), 4);
      return 4;
   when E : Ada_Quality.Reporting.Reporting_Error | Ada_Quality.Reporting.Schema_Error |
     Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Busy_Error |
     Ada_Quality.Reporting.Limit_Error =>
      Emit_Error ("reporting_error", Ada.Exceptions.Exception_Message (E), 4);
      return 4;
   when E : Usage_Error =>
      Emit_Error ("usage_error", Ada.Exceptions.Exception_Message (E), 2);
      return 2;
   when E : others =>  --  AQ: audited exception boundary
      Emit_Error ("execution_error", Ada.Exceptions.Exception_Information (E), 3);
      return 3;
end Run_Request;
