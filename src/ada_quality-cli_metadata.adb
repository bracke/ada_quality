with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Ada_Quality.CLI_Metadata is
   use Ada.Strings.Unbounded;

   type Option_Spec is record
      Name       : Unbounded_String;
      Kind       : Option_Kind;
      Repeatable : Boolean;
   end record;

   function Option_Item
     (Name : String; Kind : Option_Kind; Repeatable : Boolean := False)
      return Option_Spec is
     (To_Unbounded_String (Name), Kind, Repeatable);

   Options : constant array (Positive range <>) of Option_Spec :=
     [Option_Item ("--database", Value_Option),
      Option_Item ("--policy", Value_Option),
      Option_Item ("--color", Value_Option),
      Option_Item ("--project", Value_Option),
      Option_Item ("--format", Value_Option),
      Option_Item ("--current", Value_Option),
      Option_Item ("--baseline", Value_Option),
      Option_Item ("--indicator", Value_Option),
      Option_Item ("--changed-file", Value_Option, Repeatable => True),
      Option_Item ("--status", Value_Option),
      Option_Item ("--files-from", Value_Option),
      Option_Item ("--category", Value_Option),
      Option_Item ("--limit", Value_Option),
      Option_Item ("--since", Value_Option),
      Option_Item ("--until", Value_Option),
      Option_Item ("--from-run", Value_Option),
      Option_Item ("--to-run", Value_Option),
      Option_Item ("--only", Value_Option),
      Option_Item ("--jobs", Value_Option),
      Option_Item ("--profile", Value_Option),
      Option_Item ("--severity", Value_Option),
      Option_Item ("--path", Value_Option),
      Option_Item ("--git-diff", Value_Option),
      Option_Item ("--output", Value_Option),
      Option_Item ("--before", Value_Option),
      Option_Item ("--keep", Value_Option),
      Option_Item ("--offset", Value_Option),
      Option_Item ("--tag", Value_Option),
      Option_Item ("--sign-key", Value_Option),
      Option_Item ("--public-key", Value_Option),
      Option_Item ("--cursor", Value_Option),
      Option_Item ("--error-format", Value_Option),
      Option_Item ("--trust-store", Value_Option),
      Option_Item ("--max-failures", Value_Option),
      Option_Item ("--max-invalid", Value_Option),
      Option_Item ("--max-expiring", Value_Option),
      Option_Item ("--no-color", Flag_Option),
      Option_Item ("--all", Flag_Option),
      Option_Item ("--json", Flag_Option),
      Option_Item ("--add", Flag_Option),
      Option_Item ("--fail-on-regression", Flag_Option),
      Option_Item ("--reuse-unchanged", Flag_Option),
      Option_Item ("--project-policy", Flag_Option),
      Option_Item ("--remove-missing", Flag_Option),
      Option_Item ("--staged", Flag_Option),
      Option_Item ("--unstaged", Flag_Option),
      Option_Item ("--untracked", Flag_Option),
      Option_Item ("--dry-run", Flag_Option),
      Option_Item ("--explain", Flag_Option)];

   type Command_Spec is record
      Name, Usage, Options : Unbounded_String;
      Requires_Store       : Boolean;
   end record;

   function Command_Item
     (Name, Usage : String;
      Options : String := "";
      Requires_Store : Boolean := False) return Command_Spec is
     (To_Unbounded_String (Name), To_Unbounded_String (Usage),
      To_Unbounded_String (Options), Requires_Store);

   Commands : constant array (Registered_Command_Id) of Command_Spec :=
     [Help_Command => Command_Item ("help", ""),
      Version_Command => Command_Item ("version", ""),
      Project_Command => Command_Item
        ("project",
         "add PATH | discover ROOT [--add] | sync ROOT [--remove-missing] | list | show ID | " &
         "enable ID | disable ID | relocate ID PATH | remove ID | tag ID NAME | untag ID NAME | tags [ID]",
         "--database"),
      Check_Command => Command_Item
        ("check", "(--all | --project ID | --tag NAME) [--jobs N] [--reuse-unchanged] " &
         "[--dry-run] [--profile NAME] [--project-policy] [--json] [--output FILE]",
         "--database|--policy|--all|--project|--tag|--jobs|--reuse-unchanged|--dry-run|" &
           "--profile|--project-policy|--json|--output",
         Requires_Store => True),
      Scan_Command => Command_Item
        ("scan", "--project ID (--changed-file PATH ... | --files-from FILE|- | --git-diff BASE) " &
         "[--staged] [--unstaged] [--untracked] [--format text|json|sarif] [--output FILE]",
         "--database|--policy|--project|--changed-file|--files-from|--git-diff|--staged|" &
           "--unstaged|--untracked|--format|--json|--output"),
      Assessment_Command => Command_Item
        ("assessment",
         "show RUN_REF | diff BASELINE_REF CURRENT_REF | alias NAME RUN_ID | aliases [RUN_REF]",
         "--database"),
      History_Command => Command_Item
        ("history",
         "[--project ID] [--tag NAME] [--status STATE] [--cursor TOKEN] [--json]",
         "--database|--project|--tag|--status|--since|--until|--format|--json|--limit|" &
           "--offset|--cursor|--output"),
      Status_Command => Command_Item
        ("status",
         "[--tag NAME] [--only unhealthy|stale|regressed] [--cursor TOKEN] [--json]",
         "--database|--only|--since|--tag|--format|--json|--limit|--offset|--cursor|--output"),
      Findings_Command => Command_Item
        ("findings", "[--project ID] [--indicator ID] [--severity LEVEL] [--path TEXT] " &
         "[--format text|json|sarif] [--output FILE]",
         "--database|--project|--indicator|--severity|--path|--tag|--since|--until|--format|" &
           "--json|--limit|--offset|--cursor|--output"),
      Regressions_Command => Command_Item
        ("regressions", "[--project ID | --tag NAME] [--current RUN_REF] [--baseline RUN_REF] " &
         "[--fail-on-regression]",
         "--database|--project|--tag|--baseline|--current|--fail-on-regression|--format|" &
           "--json|--output"),
      Trend_Command => Command_Item
        ("trend", "--project ID [--tag NAME] (--indicator ID | --all) [--from-run ID] " &
         "[--to-run ID] [--since TIME] [--until TIME] [--format text|json|csv] [--output FILE]",
         "--database|--project|--tag|--indicator|--all|--from-run|--to-run|--since|--until|" &
           "--format|--json|--output"),
      Explain_Command => Command_Item ("explain", "INDICATOR_ID"),
      Indicator_Command => Command_Item ("indicator", "list [--category CATEGORY] [--format text|json]"),
      Report_Command => Command_Item
        ("report", "--format json|html [--project ID | --tag NAME] [--since TIME] [--until TIME] " &
         "[--output FILE]", "--database|--format|--project|--tag|--since|--until|--output"),
      Policy_Command => Command_Item
        ("policy",
         "init | validate | show | profiles | diff A B | impact A B | " &
         "effective --project ID [--profile NAME] [--explain]", "--policy"),
      Database_Command => Command_Item
        ("database",
         "init | check | recover | compact | stats | keygen PRIVATE PUBLIC | verify PATH | " &
         "backup PATH | export PATH | import PATH | restore PATH | archive [PATH] | merge SOURCE... | " &
         "inspect PATH | trust add KEY | trust list | trust remove KEY_ID",
         "--database|--format|--json"),
      Doctor_Command => Command_Item
        ("doctor", "(--project ID | --all | --tag NAME) [--json]",
         "--database|--policy|--project|--all|--tag|--profile|--max-failures|--format|--json|--output"),
      Waiver_Command => Command_Item
        ("waiver", "audit (--project ID | --all | --tag NAME) [--json]",
         "--database|--policy"),
      Completion_Command => Command_Item ("completion", "bash | zsh | fish")];

   type Nested_Action_Spec is record
      Command, Subcommand, Actions : Unbounded_String;
   end record;

   Nested_Actions : constant array (Positive range <>) of Nested_Action_Spec :=
     [(To_Unbounded_String ("database"), To_Unbounded_String ("trust"),
       To_Unbounded_String ("add|list|remove"))];

   function Contains_Token (List, Token : String) return Boolean is
     (List = "*" or else
      Ada.Strings.Fixed.Index ("|" & List & "|", "|" & Token & "|") > 0);

   procedure Append_Unique (Words : in out Unbounded_String; Token : String) is
   begin
      if Token /= "" and then
        Ada.Strings.Fixed.Index (" " & To_String (Words) & " ", " " & Token & " ") = 0
      then
         if Length (Words) > 0 then
            Append (Words, " ");
         end if;
         Append (Words, Token);
      end if;
   end Append_Unique;

   procedure Append_Tokens (Words : in out Unbounded_String; Tokens : String) is
      Start : Positive := Tokens'First;
      Stop  : Natural;
   begin
      if Tokens = "" or else Tokens = "*" then
         return;
      end if;
      while Start <= Tokens'Last loop
         Stop := Ada.Strings.Fixed.Index (Tokens, "|", From => Start);
         if Stop = 0 then
            Stop := Tokens'Last + 1;
         end if;
         Append_Unique (Words, Tokens (Start .. Stop - 1));
         Start := Stop + 1;
      end loop;
   end Append_Tokens;

   function Classify_Option (Name : String) return Option_Kind is
   begin
      for Item of Options loop
         if To_String (Item.Name) = Name then
            return Item.Kind;
         end if;
      end loop;
      return Not_An_Option;
   end Classify_Option;

   function Repeatable (Name : String) return Boolean is
   begin
      for Item of Options loop
         if To_String (Item.Name) = Name then
            return Item.Repeatable;
         end if;
      end loop;
      return False;
   end Repeatable;

   function Command_Count return Positive is (Commands'Length);

   function Command_Name (Index : Positive) return String is
     (To_String
        (Commands
           (Command_Id'Val
              (Command_Id'Pos (Registered_Command_Id'First) + Index - 1)).Name));

   function Identify (Name : String) return Command_Id is
   begin
      for Id in Registered_Command_Id loop
         if To_String (Commands (Id).Name) = Name then
            return Id;
         end if;
      end loop;
      return Unknown_Command;
   end Identify;

   function Is_Command (Name : String) return Boolean is
     (Identify (Name) /= Unknown_Command);

   type Subcommand_Spec is record
      Command : Command_Id;
      Name    : Unbounded_String;
      Id      : Subcommand_Id;
      Options : Unbounded_String;
      Requires_Store : Boolean;
   end record;

   function Subcommand_Item
     (Command : Command_Id; Name : String; Id : Subcommand_Id;
      Options : String := ""; Requires_Store : Boolean := False)
      return Subcommand_Spec is
     (Command, To_Unbounded_String (Name), Id, To_Unbounded_String (Options),
      Requires_Store);

   Subcommands : constant array (Positive range <>) of Subcommand_Spec :=
     [Subcommand_Item (Project_Command, "add", Project_Add, Requires_Store => True),
      Subcommand_Item
        (Project_Command, "discover", Project_Discover,
         "--add|--format|--json|--output", Requires_Store => True),
      Subcommand_Item
        (Project_Command, "sync", Project_Sync,
         "--remove-missing|--format|--json|--output", Requires_Store => True),
      Subcommand_Item
        (Project_Command, "list", Project_List,
         "--format|--json|--limit|--offset|--cursor|--output"),
      Subcommand_Item
        (Project_Command, "show", Project_Show, "--format|--json|--output"),
      Subcommand_Item (Project_Command, "enable", Project_Enable, Requires_Store => True),
      Subcommand_Item (Project_Command, "disable", Project_Disable, Requires_Store => True),
      Subcommand_Item (Project_Command, "relocate", Project_Relocate, Requires_Store => True),
      Subcommand_Item (Project_Command, "remove", Project_Remove, Requires_Store => True),
      Subcommand_Item (Project_Command, "tag", Project_Tag, Requires_Store => True),
      Subcommand_Item (Project_Command, "untag", Project_Untag, Requires_Store => True),
      Subcommand_Item
        (Project_Command, "tags", Project_Tags, "--format|--json|--output"),
      Subcommand_Item
        (Assessment_Command, "show", Assessment_Show, "--format|--json|--output"),
      Subcommand_Item
        (Assessment_Command, "diff", Assessment_Diff, "--format|--json|--output"),
      Subcommand_Item
        (Assessment_Command, "alias", Assessment_Alias, Requires_Store => True),
      Subcommand_Item
        (Assessment_Command, "aliases", Assessment_Aliases,
         "--format|--json|--limit|--offset|--cursor|--output"),
      Subcommand_Item
        (Indicator_Command, "list", Indicator_List, "--category|--format|--json|--output"),
      Subcommand_Item
        (Policy_Command, "init", Policy_Init, "--profile|--format|--json|--output"),
      Subcommand_Item
        (Policy_Command, "validate", Policy_Validate, "--profile|--format|--json|--output"),
      Subcommand_Item
        (Policy_Command, "show", Policy_Show, "--profile|--format|--json|--output"),
      Subcommand_Item
        (Policy_Command, "profiles", Policy_Profiles, "--format|--json|--output"),
      Subcommand_Item
        (Policy_Command, "effective", Policy_Effective,
         "--database|--profile|--project|--explain|--format|--json|--output"),
      Subcommand_Item
        (Policy_Command, "diff", Policy_Diff, "--format|--json|--output"),
      Subcommand_Item
        (Policy_Command, "impact", Policy_Impact,
         "--database|--project|--tag|--format|--json|--output"),
      Subcommand_Item (Database_Command, "init", Database_Init),
      Subcommand_Item (Database_Command, "check", Database_Check),
      Subcommand_Item (Database_Command, "recover", Database_Recover),
      Subcommand_Item (Database_Command, "compact", Database_Compact),
      Subcommand_Item (Database_Command, "stats", Database_Stats, "--output"),
      Subcommand_Item (Database_Command, "keygen", Database_Keygen),
      Subcommand_Item
        (Database_Command, "verify", Database_Verify,
         "--output|--public-key|--trust-store"),
      Subcommand_Item (Database_Command, "inspect", Database_Inspect, "--output"),
      Subcommand_Item
        (Database_Command, "trust", Database_Trust, "--output|--trust-store"),
      Subcommand_Item (Database_Command, "backup", Database_Backup, "--sign-key"),
      Subcommand_Item (Database_Command, "export", Database_Export, "--sign-key"),
      Subcommand_Item
        (Database_Command, "import", Database_Import, "--public-key|--trust-store"),
      Subcommand_Item
        (Database_Command, "restore", Database_Restore, "--public-key|--trust-store"),
      Subcommand_Item
        (Database_Command, "archive", Database_Archive, "--output|--dry-run|--before|--keep"),
      Subcommand_Item
        (Database_Command, "merge", Database_Merge, "--output|--dry-run"),
      Subcommand_Item
        (Waiver_Command, "audit", Waiver_Audit,
         "--project|--all|--tag|--profile|--max-invalid|--max-expiring|--format|--json|--output"),
      Subcommand_Item (Completion_Command, "bash", Completion_Bash),
      Subcommand_Item (Completion_Command, "zsh", Completion_Zsh),
      Subcommand_Item (Completion_Command, "fish", Completion_Fish)];

   function Allowed (Command, Subcommand, Option_Name : String) return Boolean is
      Command_Id_Value : constant Command_Id := Identify (Command);
   begin
      if Contains_Token ("--color|--no-color|--error-format", Option_Name) then
         return True;
      elsif Command_Id_Value = Unknown_Command then
         return False;
      elsif Contains_Token
        (To_String (Commands (Command_Id_Value).Options), Option_Name)
      then
         return True;
      end if;
      for Item of Subcommands loop
         if Item.Command = Command_Id_Value and then
           To_String (Item.Name) = Subcommand and then
           Contains_Token (To_String (Item.Options), Option_Name)
         then
            return True;
         end if;
      end loop;
      return False;
   end Allowed;

   function Subcommands_For (Command : String) return String is
      Id    : constant Command_Id := Identify (Command);
      Words : Unbounded_String;
   begin
      if Id = Unknown_Command then
         return "";
      end if;
      for Item of Subcommands loop
         if Item.Command = Id then
            if Length (Words) > 0 then
               Append (Words, "|");
            end if;
            Append (Words, To_String (Item.Name));
         end if;
      end loop;
      return To_String (Words);
   end Subcommands_For;

   function Identify_Subcommand
     (Command : Command_Id; Name : String) return Subcommand_Id
   is
   begin
      if Name = "" then
         return No_Subcommand;
      end if;
      for Item of Subcommands loop
         if Item.Command = Command and then To_String (Item.Name) = Name then
            return Item.Id;
         end if;
      end loop;
      return Unknown_Subcommand;
   end Identify_Subcommand;

   function Command_Of (Subcommand : Subcommand_Id) return Command_Id is
   begin
      for Item of Subcommands loop
         if Item.Id = Subcommand then
            return Item.Command;
         end if;
      end loop;
      return Unknown_Command;
   end Command_Of;

   function Image (Subcommand : Subcommand_Id) return String is
   begin
      if Subcommand = No_Subcommand then
         return "";
      elsif Subcommand = Unknown_Subcommand then
         return "unknown";
      end if;
      for Item of Subcommands loop
         if Item.Id = Subcommand then
            return To_String (Item.Name);
         end if;
      end loop;
      raise Program_Error with "subcommand has no metadata entry";
   end Image;

   function Requires_Store
     (Command : Command_Id; Subcommand : Subcommand_Id) return Boolean
   is
   begin
      if Command in Registered_Command_Id and then Commands (Command).Requires_Store then
         return True;
      end if;
      for Item of Subcommands loop
         if Item.Command = Command and then Item.Id = Subcommand then
            return Item.Requires_Store;
         end if;
      end loop;
      return False;
   end Requires_Store;

   function Maximum_Positional_Count
     (Command       : Command_Id;
      Subcommand    : Subcommand_Id;
      Nested_Action : String := "") return Natural
   is
   begin
      case Subcommand is
         when Project_Relocate | Project_Tag | Project_Untag |
           Assessment_Diff | Assessment_Alias | Policy_Diff | Policy_Impact |
           Database_Keygen =>
            return 4;
         when Project_List | Indicator_List | Policy_Init | Policy_Validate |
           Policy_Show | Policy_Profiles | Policy_Effective | Database_Init |
           Database_Check | Database_Recover | Database_Compact |
           Database_Stats | Waiver_Audit | Completion_Bash |
           Completion_Zsh | Completion_Fish =>
            return 2;
         when Project_Add | Project_Discover | Project_Sync | Project_Show |
           Project_Enable | Project_Disable | Project_Remove | Project_Tags |
           Assessment_Show | Assessment_Aliases | Database_Verify |
           Database_Inspect | Database_Backup | Database_Export |
           Database_Import | Database_Restore | Database_Archive =>
            return 3;
         when Database_Trust =>
            return (if Nested_Action = "list" then 3 else 4);
         when Database_Merge =>
            return Natural'Last;
         when No_Subcommand =>
            return
              (case Command is
                  when Help_Command | Version_Command | Check_Command |
                    Scan_Command | History_Command | Status_Command |
                    Findings_Command | Regressions_Command | Trend_Command |
                    Report_Command | Doctor_Command => 1,
                  when Explain_Command => 2,
                  when others => 2);
         when Unknown_Subcommand =>
            return Natural'Last;
      end case;
   end Maximum_Positional_Count;

   function Is_Subcommand (Command, Name : String) return Boolean is
     (Contains_Token (Subcommands_For (Command), Name));

   function Subcommand_Count (Command : String) return Natural is
      Id    : constant Command_Id := Identify (Command);
      Count : Natural := 0;
   begin
      for Item of Subcommands loop
         if Item.Command = Id then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Subcommand_Count;

   function Subcommand_Name (Command : String; Index : Positive) return String is
      Id    : constant Command_Id := Identify (Command);
      Count : Natural := 0;
   begin
      for Item of Subcommands loop
         if Item.Command = Id then
            Count := Count + 1;
            if Count = Index then
               return To_String (Item.Name);
            end if;
         end if;
      end loop;
      raise Constraint_Error with "subcommand index is out of range";
   end Subcommand_Name;

   function Command_Names return String is
      Words : Unbounded_String;
   begin
      for Item of Commands loop
         Append_Unique (Words, To_String (Item.Name));
      end loop;
      return To_String (Words);
   end Command_Names;

   function Completion_Words (Command, Subcommand : String) return String is
      Words : Unbounded_String;
   begin
      if Subcommand = "" then
         Append_Tokens (Words, Subcommands_For (Command));
      else
         for Item of Nested_Actions loop
            if To_String (Item.Command) = Command and then
              To_String (Item.Subcommand) = Subcommand
            then
               Append_Tokens (Words, To_String (Item.Actions));
            end if;
         end loop;
      end if;
      for Item of Options loop
         if Allowed (Command, Subcommand, To_String (Item.Name)) then
            Append_Unique (Words, To_String (Item.Name));
         end if;
      end loop;
      return To_String (Words);
   end Completion_Words;

   function Value_Option_Pattern return String is
      Words : Unbounded_String;
   begin
      for Item of Options loop
         if Item.Kind = Value_Option then
            if Length (Words) > 0 then
               Append (Words, "|");
            end if;
            Append (Words, To_String (Item.Name));
         end if;
      end loop;
      return To_String (Words);
   end Value_Option_Pattern;

   function Options_For_Command (Command : String) return String is
      Words : Unbounded_String;
   begin
      for Item of Options loop
         declare
            Name      : constant String := To_String (Item.Name);
            Permitted : Boolean := Allowed (Command, "", Name);
         begin
            if not Permitted then
               for Index in 1 .. Subcommand_Count (Command) loop
                  Permitted := Allowed (Command, Subcommand_Name (Command, Index), Name);
                  exit when Permitted;
               end loop;
            end if;
            if Permitted then
               Append_Unique (Words, Name);
            end if;
         end;
      end loop;
      return To_String (Words);
   end Options_For_Command;

   function Help_Text return String is
      Result : Unbounded_String := To_Unbounded_String
        ("ada-quality " & Ada_Quality.Version & ASCII.LF &
         "Usage: ada-quality [global options] <command> [options]" & ASCII.LF &
         ASCII.LF & "Commands:" & ASCII.LF);
   begin
      for Item of Commands loop
         Append (Result, "  " & To_String (Item.Name));
         if Length (Item.Usage) > 0 then
            Append (Result, " " & To_String (Item.Usage));
         end if;
         Append (Result, ASCII.LF);
         declare
            Accepted : constant String := Options_For_Command (To_String (Item.Name));
         begin
            if Accepted /= "" then
               Append (Result, "      options: " & Accepted & ASCII.LF);
            end if;
         end;
      end loop;
      Append
        (Result, ASCII.LF &
         "Global options: --database PATH --policy PATH --error-format text|json --no-color" & ASCII.LF);
      return To_String (Result);
   end Help_Text;
end Ada_Quality.CLI_Metadata;
