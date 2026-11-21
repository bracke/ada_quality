--  Single source of truth for CLI commands, options, help, and completion.
package Ada_Quality.CLI_Metadata is
   type Option_Kind is (Not_An_Option, Flag_Option, Value_Option);
   type Command_Id is
     (Unknown_Command, Help_Command, Version_Command, Project_Command,
      Check_Command, Scan_Command, Assessment_Command, History_Command,
      Status_Command, Findings_Command, Regressions_Command, Trend_Command,
      Explain_Command, Indicator_Command, Report_Command, Policy_Command,
      Database_Command, Doctor_Command, Waiver_Command, Completion_Command);
   subtype Registered_Command_Id is Command_Id range Help_Command .. Completion_Command;
   type Subcommand_Id is
     (No_Subcommand, Unknown_Subcommand,
      Project_Add, Project_Discover, Project_Sync, Project_List, Project_Show,
      Project_Enable, Project_Disable, Project_Relocate, Project_Remove,
      Project_Tag, Project_Untag, Project_Tags,
      Assessment_Show, Assessment_Diff, Assessment_Alias, Assessment_Aliases,
      Indicator_List, Policy_Init, Policy_Validate, Policy_Show,
      Policy_Profiles, Policy_Effective, Policy_Diff, Policy_Impact,
      Database_Init, Database_Check, Database_Recover, Database_Compact,
      Database_Stats, Database_Keygen, Database_Verify, Database_Inspect,
      Database_Trust, Database_Backup, Database_Export, Database_Import,
      Database_Restore, Database_Archive, Database_Merge,
      Waiver_Audit, Completion_Bash, Completion_Zsh, Completion_Fish);

   function Classify_Option (Name : String) return Option_Kind;
   function Repeatable (Name : String) return Boolean;
   function Allowed (Command, Subcommand, Option_Name : String) return Boolean;
   function Is_Command (Name : String) return Boolean;
   function Is_Subcommand (Command, Name : String) return Boolean;
   function Identify (Name : String) return Command_Id;
   function Identify_Subcommand
     (Command : Command_Id; Name : String) return Subcommand_Id;
   function Command_Of (Subcommand : Subcommand_Id) return Command_Id;
   function Image (Subcommand : Subcommand_Id) return String;
   function Requires_Store
     (Command : Command_Id; Subcommand : Subcommand_Id) return Boolean;
   function Maximum_Positional_Count
     (Command       : Command_Id;
      Subcommand    : Subcommand_Id;
      Nested_Action : String := "") return Natural;

   function Command_Count return Positive;
   function Command_Name (Index : Positive) return String;
   function Subcommand_Count (Command : String) return Natural;
   function Subcommand_Name (Command : String; Index : Positive) return String;

   function Command_Names return String;
   function Completion_Words (Command, Subcommand : String) return String;
   function Value_Option_Pattern return String;
   function Help_Text return String;
end Ada_Quality.CLI_Metadata;
