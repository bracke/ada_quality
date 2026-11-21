with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Task_Attributes;
with Ada.Text_IO;
with Terminal_Styles;
with Ada_Quality.Command_Models;
with Ada_Quality.CLI_Changed_Files;
with Ada_Quality.CLI_Cursors;
with Ada_Quality.CLI_Metadata;
with Ada_Quality.CLI_Pagination;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.JSON_Administration;
with Ada_Quality.Pagination;
with Ada_Quality.Presentation;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Project_Tools.Files;

package body Ada_Quality.CLI is
   use Ada.Strings.Unbounded;
   use Ada_Quality.CLI_Metadata;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.History.Comparison_Status;
   use type Ada_Quality.Indicators.Indicator_Category;
   use type Ada_Quality.Indicators.Metric_Direction;
   use type Ada.Directories.File_Kind;

   package Text_Vectors renames Ada_Quality.CLI_Changed_Files.String_Vectors;

   Usage_Error : exception;

   Process_Arguments : constant Ada_Quality.CLI_Arguments.Argument_Set :=
     Ada_Quality.CLI_Arguments.Capture;

   type Argument_Context is record
      Arguments  : Ada_Quality.CLI_Arguments.Argument_Set;
      Overridden : Boolean := False;
   end record;

   Default_Argument_Context : constant Argument_Context := (others => <>);

   package Argument_Contexts is new Ada.Task_Attributes
     (Attribute     => Argument_Context,
      Initial_Value => Default_Argument_Context);

   protected Request_Guard is
      entry Acquire;
      procedure Release;
   private
      Available : Boolean := True;
   end Request_Guard;

   protected body Request_Guard is
      entry Acquire when Available is
      begin
         Available := False;
      end Acquire;

      procedure Release is
      begin
         Available := True;
      end Release;
   end Request_Guard;

   package Request_Depths is new Ada.Task_Attributes
     (Attribute => Natural, Initial_Value => 0);

   function Current_Arguments
     return Ada_Quality.CLI_Arguments.Argument_Set
   is
      Context : constant Argument_Context := Argument_Contexts.Value;
   begin
      return (if Context.Overridden then Context.Arguments else Process_Arguments);
   end Current_Arguments;

   function Argument (Index : Positive) return String is
     (Ada_Quality.CLI_Arguments.Element (Current_Arguments, Index));

   function Argument_Count return Natural is
     (Ada_Quality.CLI_Arguments.Count (Current_Arguments));

   function Option (Name, Default : String) return String is
     (Ada_Quality.CLI_Arguments.Option
        (Current_Arguments, Name, Default));

   function Starts_With (Text, Prefix : String) return Boolean is
     (Text'Length >= Prefix'Length and then
      Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix);

   function Has_Tag (Tags, Name : String) return Boolean is
     (Name /= "" and then Ada.Strings.Fixed.Index ("," & Tags & ",", "," & Name & ",") > 0);

   function Has_Flag (Name : String) return Boolean is
     (Ada_Quality.CLI_Arguments.Has_Flag (Current_Arguments, Name));

   function Selected_Output_Format
     (Default, Allowed, Error_Message : String) return String
   is
      Requested : constant String := Option ("--format", "");
      Result    : constant String :=
        (if Has_Flag ("--json") then "json"
         elsif Requested = "" then Default
         else Requested);
   begin
      if Has_Flag ("--json") and then Requested not in "" | "json" then
         raise Usage_Error with "--json conflicts with non-JSON --format";
      elsif Ada.Strings.Fixed.Index
        ("|" & Allowed & "|", "|" & Result & "|") = 0
      then
         raise Usage_Error with Error_Message;
      end if;
      return Result;
   end Selected_Output_Format;

   subtype Option_Kind is Ada_Quality.CLI_Metadata.Option_Kind;
   Not_An_Option : constant Option_Kind := Ada_Quality.CLI_Metadata.Not_An_Option;
   Flag_Option   : constant Option_Kind := Ada_Quality.CLI_Metadata.Flag_Option;
   Value_Option  : constant Option_Kind := Ada_Quality.CLI_Metadata.Value_Option;

   function Classify_Option (Name : String) return Option_Kind
     renames Ada_Quality.CLI_Metadata.Classify_Option;

   function Positional (Index : Positive) return String;

   function Positional_Count return Natural is
      Count      : Natural := 0;
      Skip_Value : Boolean := False;
   begin
      for Index in 1 .. Argument_Count loop
         if Skip_Value then
            Skip_Value := False;
         elsif Classify_Option (Argument (Index)) = Value_Option then
            Skip_Value := True;
         elsif Classify_Option (Argument (Index)) = Not_An_Option then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Positional_Count;

   function Allowed_For_Command (Name : String) return Boolean is
      Command    : constant String := Positional (1);
      Subcommand : constant String := Positional (2);
   begin
      return Ada_Quality.CLI_Metadata.Allowed (Command, Subcommand, Name);
   end Allowed_For_Command;

   function Positional (Index : Positive) return String is
      Count      : Natural := 0;
      Skip_Value : Boolean := False;
   begin
      for J in 1 .. Argument_Count loop
         declare
            Value : constant String := Argument (J);
         begin
            if Skip_Value then
               Skip_Value := False;
            elsif Classify_Option (Value) = Value_Option then
               Skip_Value := True;
            elsif Classify_Option (Value) = Flag_Option then
               null;
            else
               Count := Count + 1;
               if Count = Index then return Value; end if;
            end if;
         end;
      end loop;
      return "";
   end Positional;

   procedure Validate_Option_Syntax is
      Index : Positive := 1;
   begin
      while Index <= Argument_Count loop
         declare
            Value : constant String := Argument (Index);
         begin
            if Starts_With (Value, "--") then
               if not Ada_Quality.CLI_Metadata.Repeatable (Value) then
                  for Previous in 1 .. Index - 1 loop
                     if Argument (Previous) = Value then
                        raise Usage_Error with "duplicate option: " & Value;
                     end if;
                  end loop;
               end if;
               if Classify_Option (Value) = Not_An_Option then
                  raise Usage_Error with "unknown option: " & Value;
               elsif not Allowed_For_Command (Value) then
                  raise Usage_Error with "option is not valid for this command: " & Value;
               elsif Classify_Option (Value) = Value_Option then
                  if Index = Argument_Count or else
                    Starts_With (Argument (Index + 1), "--")
                  then
                     raise Usage_Error with "option requires a value: " & Value;
                  end if;
                  Index := Index + 1;
               end if;
            end if;
         end;
         Index := Index + 1;
      end loop;
   end Validate_Option_Syntax;

   procedure Validate_Global_Options is
   begin
      if Option ("--color", "never") not in "never" | "auto" | "always" then
         raise Usage_Error with "--color requires never, auto, or always";
      elsif Option ("--error-format", "text") not in "text" | "json" then
         raise Usage_Error with "--error-format requires text or json";
      elsif Has_Flag ("--json") and then Option ("--format", "") not in "" | "json" then
         raise Usage_Error with "--json conflicts with non-JSON --format";
      end if;
   end Validate_Global_Options;

   procedure Validate_Check_Selectors is
   begin
      if Positional (1) = "check" and then Option ("--project", "") /= "" and then
        (Has_Flag ("--all") or else Option ("--tag", "") /= "")
      then
         raise Usage_Error with "--all, --project, and --tag selectors are mutually exclusive";
      elsif Positional (1) = "check" and then Has_Flag ("--all") and then Option ("--tag", "") /= "" then
         raise Usage_Error with "--all, --project, and --tag selectors are mutually exclusive";
      end if;
   end Validate_Check_Selectors;

   procedure Validate_Audit_Selectors is
   begin
      if Positional (1) in "doctor" | "waiver" then
         declare
            Selectors : constant Natural :=
              (if Option ("--project", "") /= "" then 1 else 0) +
              (if Has_Flag ("--all") then 1 else 0) +
              (if Option ("--tag", "") /= "" then 1 else 0);
         begin
            if Selectors > 1 then
               raise Usage_Error with "--all, --project, and --tag selectors are mutually exclusive";
            elsif Positional (1) = "waiver" and then Selectors = 0 then
               raise Usage_Error with "waiver audit requires --project, --all, or --tag";
            end if;
         end;
      end if;
   end Validate_Audit_Selectors;

   procedure Validate_Options
     (Command : Command_Id; Subcommand : Subcommand_Id) is
      Maximum : constant Natural :=
        Ada_Quality.CLI_Metadata.Maximum_Positional_Count
          (Command, Subcommand, Positional (3));
   begin
      Validate_Option_Syntax;
      if Maximum /= Natural'Last and then Positional_Count > Maximum then
         raise Usage_Error with
           "unexpected positional argument: " & Positional (Maximum + 1);
      end if;
      Validate_Global_Options;
      Validate_Check_Selectors;
      Validate_Audit_Selectors;
   end Validate_Options;

   function Default_Database return String is
   begin
      if Ada.Environment_Variables.Exists ("ADA_QUALITY_DATABASE") then
         return Ada.Environment_Variables.Value ("ADA_QUALITY_DATABASE");
      end if;
      return ".ada-quality.db";
   end Default_Database;

   function Default_Policy return String is
   begin
      if Ada.Environment_Variables.Exists ("ADA_QUALITY_POLICY") then
         return Ada.Environment_Variables.Value ("ADA_QUALITY_POLICY");
      end if;
      return "quality-policy.toml";
   end Default_Policy;

   procedure Help is
   begin
      Ada.Text_IO.Put (Ada_Quality.CLI_Metadata.Help_Text);
   end Help;

   function Project_Text (P : Ada_Quality.Reporting.Project_Record) return String is
     (Positive'Image (P.Id) & "  " & To_String (P.Path) & "  " &
      (if P.Removed then "removed" elsif P.Enabled then "enabled" else "disabled") &
      (if Length (P.Tags) = 0 then "" else "  tags=" & To_String (P.Tags)));

   function Result_Exit (Value : Assessment) return Natural is
      Has_Violation  : Boolean := False;
      Has_Incomplete : Boolean := False;
   begin
      for R of Value.Results loop
         Has_Violation := Has_Violation or else R.Compliance = Violation;
         Has_Incomplete := Has_Incomplete or else R.Execution in Blocked | Failed | Errored;
      end loop;
      if Value.Status /= Assessment_Completed or else Has_Incomplete then return 3;
      elsif Has_Violation then return 1;
      else return 0;
      end if;
   end Result_Exit;

   function Assessment_Text (Value : Assessment) return String is
      Role : Terminal_Styles.Style_Role;
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for R of Value.Results loop
         Role :=
           (if R.Compliance = Pass then Terminal_Styles.Role_Success
            elsif R.Compliance = Violation then Terminal_Styles.Role_Error
            elsif R.Execution = Not_Applicable then Terminal_Styles.Role_Muted
            else Terminal_Styles.Role_Warning);
         Append
           (Result, Terminal_Styles.Decorate
              (Ada_Quality.Presentation.Result_Line
                 (Terminal_Styles.Marker (Role), Image (R.Indicator), To_String (R.Summary)), Role) & ASCII.LF);
      end loop;
      return To_String (Result);
   end Assessment_Text;

   procedure Emit_Document (Text : String) is
   begin
      if Option ("--output", "") = "" then
         Ada.Text_IO.Put (Text);
         if Text'Length = 0 or else Text (Text'Last) /= ASCII.LF then
            Ada.Text_IO.New_Line;
         end if;
      else
         Project_Tools.Files.Write_Text_File (Option ("--output", ""), Text);
      end if;
   end Emit_Document;

   procedure Emit_Error (Code, Message : String; Status : Natural) is
   begin
      if Option ("--error-format", "text") = "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Ada_Quality.JSON_Administration.Render_Error
              (Code, Message, Positional (1), Status, Pretty => False));
      else
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Message);
      end if;
   end Emit_Error;

   function Stored_Assessment
     (Session : Ada_Quality.Reporting.Session;
      Run_Id  : Positive) return Assessment
   is
      Stored  : constant Ada_Quality.Reporting.Assessment_Record :=
        Ada_Quality.Reporting.Read_Assessment (Session, Run_Id);
      Project : constant Ada_Quality.Reporting.Project_Record :=
        Ada_Quality.Reporting.Project (Session, Stored.Run.Project_Id);
      Result  : Assessment;
   begin
      Result.Id := Stored.Run.Id;
      Result.Project_Id := Stored.Run.Project_Id;
      Result.Project_Path := Project.Path;
      Result.Source_Fingerprint := Stored.Run.Source_Id;
      Result.Policy_Fingerprint := Stored.Run.Policy_Id;
      Result.Toolchain_Fingerprint := Stored.Run.Toolchain_Id;
      Result.Status := Stored.Run.State;
      Result.Results := Stored.Results;
      for Execution of Stored.Executions loop
         Result.Executions.Append
           (Tool_Execution'
              (Tool => Execution.Tool, Command => Execution.Command,
               Status => Execution.Status, Exit_Code => Execution.Exit_Code,
               Output_Digest => Execution.Output_Digest,
               Output_Bytes => Execution.Output_Bytes, Truncated => Execution.Truncated));
      end loop;
      return Result;
   end Stored_Assessment;

   function Comparison_Text
     (Comparison : Ada_Quality.Reporting.Project_Comparison) return String
   is
      Result : Ada.Strings.Unbounded.Unbounded_String;
      procedure Put_Line (Text : String) is
      begin
         Append (Result, Text & ASCII.LF);
      end Put_Line;
   begin
      if Comparison.Selection.Status = Ada_Quality.History.Comparison_Available then
         if Comparison.Changes.Is_Empty then
            Put_Line
              ("project" & Positive'Image (Comparison.Project_Id) &
               ": no regressions in comparable assessments");
         else
            for Change of Comparison.Changes loop
               Put_Line
                 ("project" & Positive'Image (Comparison.Project_Id) & " " &
                  Image (Change.Indicator) & " " & Ada_Quality.History.Image (Change.Kind) & ": " &
                  To_String (Change.Before) & " -> " & To_String (Change.After));
            end loop;
         end if;
      else
         Put_Line
           ("project" & Positive'Image (Comparison.Project_Id) &
            ": comparison unavailable: " &
            (case Comparison.Selection.Status is
                when Ada_Quality.History.No_Assessments => "no assessments exist",
                when Ada_Quality.History.No_Baseline => "no baseline assessment exists",
                when Ada_Quality.History.Current_Incomplete => "current assessment is not completed",
                when Ada_Quality.History.No_Completed_Baseline => "no completed baseline exists",
                when Ada_Quality.History.Toolchain_Changed => "toolchain fingerprint changed",
                when Ada_Quality.History.No_Compatible_Baseline => "no compatible baseline exists",
                when Ada_Quality.History.Comparison_Available => "comparison is available"));
      end if;
      return To_String (Result);
   end Comparison_Text;

   function Positive_Option (Name, Kind : String) return Positive;
   function Timestamp_Option (Name : String) return Ada_Quality.Reporting.Optional_Timestamp;
   function In_Time_Range
     (Value, Since_Time, Until_Time : Ada_Quality.Reporting.Optional_Timestamp) return Boolean;

   procedure Parse_Cursor
     (Cursor : String; Version, Binding, Primary, Secondary, Tertiary, Offset : out Natural)
   is
      State : constant Ada_Quality.CLI_Cursors.Cursor_State :=
        Ada_Quality.CLI_Cursors.Decode (Cursor);
   begin
      Version := State.Version;
      Binding := State.Binding;
      Primary := State.Primary;
      Secondary := State.Secondary;
      Tertiary := State.Tertiary;
      Offset := State.Offset;
   exception
      when Ada_Quality.CLI_Cursors.Cursor_Error =>
         raise Usage_Error with "invalid cursor";
   end Parse_Cursor;

   function Query_Binding (Query : String) return Positive
     renames Ada_Quality.CLI_Cursors.Query_Binding;

   procedure Require_Query_Binding (Expected : Natural) is
      Cursor : constant String := Option ("--cursor", "");
      Version, Binding, Primary, Secondary, Tertiary, Offset : Natural;
   begin
      if Cursor = "" then return; end if;
      Parse_Cursor (Cursor, Version, Binding, Primary, Secondary, Tertiary, Offset);
      if not Ada_Quality.CLI_Cursors.Belongs_To
        ((Version   => Version,
          Binding   => Binding,
          Primary   => Primary,
          Secondary => Secondary,
          Tertiary  => Tertiary,
          Offset    => Offset),
         Positive (Expected))
      then
         raise Usage_Error with "cursor does not belong to this command and filter set";
      end if;
   end Require_Query_Binding;

   function Page_Offset return Natural is
      Cursor : constant String := Option ("--cursor", "");
      Version, Binding, Primary, Secondary, Tertiary, Offset : Natural;
   begin
      if Cursor = "" then
         return (if Option ("--offset", "") = "" then 0
                 else Natural'Value (Option ("--offset", "")));
      elsif Option ("--offset", "") /= "" then
         raise Usage_Error with "--cursor and --offset are mutually exclusive";
      end if;
      Parse_Cursor (Cursor, Version, Binding, Primary, Secondary, Tertiary, Offset);
      return Offset;
   exception
      when Constraint_Error => raise Usage_Error with "invalid cursor";
   end Page_Offset;

   function Requested_Page return Ada_Quality.Pagination.Page_Request is
   begin
      return
        (Offset => Page_Offset,
         Limit  =>
           (if Option ("--limit", "") = "" then 0
            else Positive'Value (Option ("--limit", ""))));
   exception
      when Constraint_Error =>
         raise Usage_Error with
           "--offset and --limit require nonnegative and positive counts";
   end Requested_Page;

   function Cursor_Snapshot (Default : Natural) return Natural is
      Cursor : constant String := Option ("--cursor", "");
      Version, Binding, Primary, Secondary, Tertiary, Offset : Natural;
   begin
      if Cursor = "" then return Default; end if;
      Parse_Cursor (Cursor, Version, Binding, Primary, Secondary, Tertiary, Offset);
      return (if Version = 1 then Default else Primary);
   end Cursor_Snapshot;

   function Cursor_Secondary_Snapshot (Default : Natural) return Natural is
      Cursor : constant String := Option ("--cursor", "");
      Version, Binding, Primary, Secondary, Tertiary, Offset : Natural;
   begin
      if Cursor = "" then return Default; end if;
      Parse_Cursor (Cursor, Version, Binding, Primary, Secondary, Tertiary, Offset);
      return (if Version in 3 | 4 | 5 then Secondary else Default);
   end Cursor_Secondary_Snapshot;

   function Cursor_Tertiary_Snapshot (Default : Natural) return Natural is
      Cursor : constant String := Option ("--cursor", "");
      Version, Binding, Primary, Secondary, Tertiary, Offset : Natural;
   begin
      if Cursor = "" then return Default; end if;
      Parse_Cursor (Cursor, Version, Binding, Primary, Secondary, Tertiary, Offset);
      return (if Version in 4 | 5 then Tertiary else Default);
   end Cursor_Tertiary_Snapshot;

   function Cursor_Version return Natural is
      Cursor : constant String := Option ("--cursor", "");
      Version, Binding, Primary, Secondary, Tertiary, Offset : Natural;
   begin
      if Cursor = "" then return 0; end if;
      Parse_Cursor (Cursor, Version, Binding, Primary, Secondary, Tertiary, Offset);
      return Version;
   end Cursor_Version;

   function Assessment_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural
      renames Ada_Quality.CLI_Pagination.Assessment_Snapshot;

   function Alias_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural
      renames Ada_Quality.CLI_Pagination.Alias_Snapshot;

   function Project_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural
      renames Ada_Quality.CLI_Pagination.Project_Snapshot;

   function Project_Revision
     (Session : Ada_Quality.Reporting.Session; Boundary : Natural) return Natural
      renames Ada_Quality.CLI_Pagination.Project_Revision;

   procedure Require_Project_Revision
     (Session : Ada_Quality.Reporting.Session; Boundary, Expected : Natural)
   is
   begin
      if Project_Revision (Session, Boundary) /= Expected then
         raise Usage_Error with "cursor snapshot is stale because project state changed";
      end if;
   end Require_Project_Revision;

   function Page_Metadata
     (Total, Offset, Returned, Requested_Limit : Natural;
      Snapshot : Natural := 0;
      Secondary_Snapshot : Natural := 0;
      Tertiary_Snapshot : Natural := 0;
      Binding : Natural := 0) return Ada_Quality.Command_Models.Page_Info
      renames Ada_Quality.CLI_Pagination.Page_Metadata;

   procedure Print_Findings (DB_Path : String) is separate;

   function Run_Check
     (Store : in out Ada_Quality.Storage.Store;
      Policy_Path : String) return Natural is separate;

   function Run_Policy_Impact
     (DB_Path, Policy_Path : String) return Natural is separate;

   function Run_Policy
     (DB_Path, Policy_Path : String;
      Subcommand : Subcommand_Id) return Natural is separate;

   function Changed_Files return Text_Vectors.Vector is
   begin
      return Ada_Quality.CLI_Changed_Files.Read (Current_Arguments);
   exception
      when E : Ada_Quality.CLI_Changed_Files.Input_Error =>
         raise Usage_Error with Ada.Exceptions.Exception_Message (E);
   end Changed_Files;

   function Run_Database
     (DB_Path : String; Operation : Subcommand_Id) return Natural is separate;

   function Run_Doctor (DB_Path, Policy_Path : String) return Natural is separate;

   function Run_Waiver_Audit (DB_Path, Policy_Path : String) return Natural is separate;

   function Run_Scan (DB_Path, Policy_Path : String) return Natural is separate;

   function Run_Explain (Name : String) return Natural is separate;

   function Run_Status (DB_Path : String) return Natural is separate;

   function Run_Indicator_List return Natural is separate;

   function Run_Project_Discover
     (Store : in out Ada_Quality.Storage.Store;
      Root : String;
      Add, Remove_Missing : Boolean) return Natural
   is separate;

   function Positive_Option (Name, Kind : String) return Positive is
   begin
      return Positive'Value (Option (Name, ""));
   exception
      when Constraint_Error =>
         raise Usage_Error with "a positive " & Kind & " ID is required";
   end Positive_Option;

   function Timestamp_Option (Name : String) return Ada_Quality.Reporting.Optional_Timestamp is
      Text : constant String := Option (Name, "");

      function Number_At (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then raise Constraint_Error; end if;
            Result := Result * 10 + Character'Pos (Text (Index)) - Character'Pos ('0');
         end loop;
         return Result;
      end Number_At;
   begin
      if Text'Length = 0 then return (Present => False); end if;
      if Text'Length /= 20 or else Text (Text'First + 4) /= '-' or else
        Text (Text'First + 7) /= '-' or else Text (Text'First + 10) /= 'T' or else
        Text (Text'First + 13) /= ':' or else Text (Text'First + 16) /= ':' or else
        Text (Text'Last) /= 'Z'
      then
         raise Constraint_Error;
      end if;
      declare
         First : constant Positive := Text'First;
      begin
         return
           (Present => True,
            Value => Ada.Calendar.Formatting.Time_Of
              (Year => Ada.Calendar.Year_Number (Number_At (First, First + 3)),
               Month => Ada.Calendar.Month_Number (Number_At (First + 5, First + 6)),
               Day => Ada.Calendar.Day_Number (Number_At (First + 8, First + 9)),
               Hour => Ada.Calendar.Formatting.Hour_Number (Number_At (First + 11, First + 12)),
               Minute => Ada.Calendar.Formatting.Minute_Number (Number_At (First + 14, First + 15)),
               Second => Ada.Calendar.Formatting.Second_Number (Number_At (First + 17, First + 18)),
               Time_Zone => 0));
      end;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         raise Usage_Error with Name & " requires YYYY-MM-DDTHH:MM:SSZ";
   end Timestamp_Option;

   function In_Time_Range
     (Value, Since_Time, Until_Time : Ada_Quality.Reporting.Optional_Timestamp) return Boolean
   is
      use type Ada.Calendar.Time;
   begin
      if not Since_Time.Present and then not Until_Time.Present then return True; end if;
      return Value.Present and then
        (not Since_Time.Present or else Value.Value >= Since_Time.Value) and then
        (not Until_Time.Present or else Value.Value <= Until_Time.Value);
   end In_Time_Range;

   function Run_Project
     (Store : in out Ada_Quality.Storage.Store;
      DB_Path : String;
      Subcommand : Subcommand_Id) return Natural
   is separate;

   function Run_Assessment
     (Store : in out Ada_Quality.Storage.Store;
      DB_Path : String;
      Subcommand : Subcommand_Id) return Natural
   is separate;

   function Run_Regressions (DB_Path : String) return Natural is separate;

   function Run_Report (DB_Path : String) return Natural is separate;

   function Run_History (DB_Path : String) return Natural is separate;

   function Run_Trend (DB_Path : String) return Natural is separate;

   function Run_Completion
     (Shell : Subcommand_Id) return Natural is separate;

   function Run_Request return Natural is separate;

   procedure Enter_Request
     (Saved_Color : out Terminal_Styles.Color_Policy;
      Top_Level   : out Boolean)
   is
      Depth : constant Natural := Request_Depths.Value;
   begin
      Top_Level := Depth = 0;
      if Top_Level then
         Request_Guard.Acquire;
      end if;
      Saved_Color := Terminal_Styles.Current_Color_Policy;
      Request_Depths.Set_Value (Depth + 1);
   end Enter_Request;

   procedure Leave_Request
     (Saved_Color : Terminal_Styles.Color_Policy;
      Top_Level   : Boolean) is
   begin
      Terminal_Styles.Set_Color_Policy (Saved_Color);
      Request_Depths.Set_Value (Request_Depths.Value - 1);
      if Top_Level then
         Request_Guard.Release;
      end if;
   end Leave_Request;

   function Run return Natural is
      Saved_Color : Terminal_Styles.Color_Policy := Terminal_Styles.Color_Auto;
      Top_Level   : Boolean := False;
      Entered     : Boolean := False;
      Result      : Natural;
   begin
      Enter_Request (Saved_Color, Top_Level);
      Entered := True;
      Result := Run_Request;
      Leave_Request (Saved_Color, Top_Level);
      return Result;
   exception
      when others =>
         if Entered then
            Leave_Request (Saved_Color, Top_Level);
         end if;
         raise;
   end Run;

   function Run
     (Arguments : Ada_Quality.CLI_Arguments.Argument_Set) return Natural
   is
      Saved       : constant Argument_Context := Argument_Contexts.Value;
      Saved_Color : Terminal_Styles.Color_Policy := Terminal_Styles.Color_Auto;
      Top_Level   : Boolean := False;
      Entered     : Boolean := False;
      Result      : Natural;
   begin
      Enter_Request (Saved_Color, Top_Level);
      Entered := True;
      Argument_Contexts.Set_Value
        ((Arguments => Arguments, Overridden => True));
      Result := Run_Request;
      Argument_Contexts.Set_Value (Saved);
      Leave_Request (Saved_Color, Top_Level);
      return Result;
   exception
      when others =>
         Argument_Contexts.Set_Value (Saved);
         if Entered then
            Leave_Request (Saved_Color, Top_Level);
         end if;
         raise;
   end Run;
end Ada_Quality.CLI;
