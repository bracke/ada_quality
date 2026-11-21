separate (Ada_Quality.CLI)
function Run_Completion (Shell : Subcommand_Id) return Natural is
   Commands : constant String := Ada_Quality.CLI_Metadata.Command_Names;

   procedure Emit_Bash_Cases is
   begin
      for Index in 1 .. Ada_Quality.CLI_Metadata.Command_Count loop
         declare
            Name : constant String := Ada_Quality.CLI_Metadata.Command_Name (Index);
         begin
            for Sub_Index in 1 .. Ada_Quality.CLI_Metadata.Subcommand_Count (Name) loop
               declare
                  Subcommand : constant String :=
                    Ada_Quality.CLI_Metadata.Subcommand_Name (Name, Sub_Index);
               begin
                  Ada.Text_IO.Put_Line
                    ("    " & Name & ":" & Subcommand & ") words='" &
                     Ada_Quality.CLI_Metadata.Completion_Words (Name, Subcommand) & "' ;;");
               end;
            end loop;
            Ada.Text_IO.Put_Line
              ("    " & Name & ":*) words='" &
               Ada_Quality.CLI_Metadata.Completion_Words (Name, "") & "' ;;");
         end;
      end loop;
   end Emit_Bash_Cases;

   procedure Emit_Zsh_Cases is
   begin
      for Index in 1 .. Ada_Quality.CLI_Metadata.Command_Count loop
         declare
            Name : constant String := Ada_Quality.CLI_Metadata.Command_Name (Index);
         begin
            for Sub_Index in 1 .. Ada_Quality.CLI_Metadata.Subcommand_Count (Name) loop
               declare
                  Subcommand : constant String :=
                    Ada_Quality.CLI_Metadata.Subcommand_Name (Name, Sub_Index);
               begin
                  Ada.Text_IO.Put_Line
                    ("      " & Name & ":" & Subcommand & ") _values 'argument' " &
                     Ada_Quality.CLI_Metadata.Completion_Words (Name, Subcommand) & " ;;");
               end;
            end loop;
            Ada.Text_IO.Put_Line
              ("      " & Name & ":*) _values 'argument' " &
               Ada_Quality.CLI_Metadata.Completion_Words (Name, "") & " ;;");
         end;
      end loop;
   end Emit_Zsh_Cases;
begin
   if Shell = No_Subcommand then
      raise Usage_Error with "completion requires bash, zsh, or fish";
   elsif Shell = Completion_Bash then
      Ada.Text_IO.Put_Line ("_ada_quality_complete() {");
      Ada.Text_IO.Put_Line ("  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]} words");
      Ada.Text_IO.Put_Line ("  local command= subcommand= token i skip=0");
      Ada.Text_IO.Put_Line ("  for ((i=1; i<COMP_CWORD; i++)); do");
      Ada.Text_IO.Put_Line ("    token=${COMP_WORDS[i]}");
      Ada.Text_IO.Put_Line ("    if ((skip)); then skip=0; continue; fi");
      Ada.Text_IO.Put_Line ("    case ""$token"" in");
      Ada.Text_IO.Put_Line
        ("      " & Ada_Quality.CLI_Metadata.Value_Option_Pattern & ") skip=1 ;;");
      Ada.Text_IO.Put_Line ("      --*) ;;");
      Ada.Text_IO.Put_Line
        ("      *) if [[ -z $command ]]; then command=$token; " &
         "elif [[ -z $subcommand ]]; then subcommand=$token; fi ;;");
      Ada.Text_IO.Put_Line ("    esac");
      Ada.Text_IO.Put_Line ("  done");
      Ada.Text_IO.Put_Line ("  case ""$prev"" in");
      Ada.Text_IO.Put_Line
        ("    --project) words=$(ada-quality project list 2>/dev/null | awk '{print $1}') ;;");
      Ada.Text_IO.Put_Line
        ("    --indicator) words=$(ada-quality indicator list 2>/dev/null | awk '{print $1}') ;;");
      Ada.Text_IO.Put_Line
        ("    --profile) words=$(ada-quality policy profiles 2>/dev/null) ;;");
      Ada.Text_IO.Put_Line ("  esac");
      Ada.Text_IO.Put_Line
        ("  if [[ -n $words ]]; then COMPREPLY=($(compgen -W ""$words"" -- ""$cur"")); return; fi");
      Ada.Text_IO.Put_Line ("  case ""$command:$subcommand"" in");
      Emit_Bash_Cases;
      Ada.Text_IO.Put_Line
        ("    *) words='" & Commands & " --color --no-color --error-format' ;;");
      Ada.Text_IO.Put_Line ("  esac");
      Ada.Text_IO.Put_Line ("  COMPREPLY=($(compgen -W ""$words"" -- ""$cur""))");
      Ada.Text_IO.Put_Line ("}");
      Ada.Text_IO.Put_Line ("complete -F _ada_quality_complete ada-quality");
   elsif Shell = Completion_Zsh then
      Ada.Text_IO.Put_Line ("#compdef ada-quality");
      Ada.Text_IO.Put_Line ("local -a aq_projects aq_aliases aq_profiles aq_indicators");
      Ada.Text_IO.Put_Line
        ("aq_projects=(${(f)""$(ada-quality project list 2>/dev/null | awk '{print $1}')""})");
      Ada.Text_IO.Put_Line
        ("aq_aliases=(${(f)""$(ada-quality assessment aliases 2>/dev/null | awk '{print $1}')""})");
      Ada.Text_IO.Put_Line
        ("aq_profiles=(${(f)""$(ada-quality policy profiles 2>/dev/null)""})");
      Ada.Text_IO.Put_Line
        ("aq_indicators=(${(f)""$(ada-quality indicator list 2>/dev/null | awk '{print $1}')""})");
      Ada.Text_IO.Put_Line
        ("_arguments '1:command:(" & Commands & ")' '*::argument:->args'");
      Ada.Text_IO.Put_Line ("case $state in");
      Ada.Text_IO.Put_Line ("  args)");
      Ada.Text_IO.Put_Line ("    case $words[2]:$words[3] in");
      Emit_Zsh_Cases;
      Ada.Text_IO.Put_Line ("    esac");
      Ada.Text_IO.Put_Line ("  ;;");
      Ada.Text_IO.Put_Line ("esac");
   elsif Shell = Completion_Fish then
      Ada.Text_IO.Put_Line
        ("complete -c ada-quality -f -n '__fish_use_subcommand' -a '" & Commands & "'");
      for Index in 1 .. Ada_Quality.CLI_Metadata.Command_Count loop
         declare
            Name : constant String := Ada_Quality.CLI_Metadata.Command_Name (Index);
            Condition : Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String
                ("__fish_seen_subcommand_from " & Name);
         begin
            if Ada_Quality.CLI_Metadata.Subcommand_Count (Name) > 0 then
               Ada.Strings.Unbounded.Append
                 (Condition, "; and not __fish_seen_subcommand_from");
               for Sub_Index in 1 .. Ada_Quality.CLI_Metadata.Subcommand_Count (Name) loop
                  Ada.Strings.Unbounded.Append
                    (Condition,
                     " " & Ada_Quality.CLI_Metadata.Subcommand_Name (Name, Sub_Index));
               end loop;
            end if;
            Ada.Text_IO.Put_Line
              ("complete -c ada-quality -n '" &
               Ada.Strings.Unbounded.To_String (Condition) & "' -a '" &
               Ada_Quality.CLI_Metadata.Completion_Words (Name, "") & "'");
            for Sub_Index in 1 .. Ada_Quality.CLI_Metadata.Subcommand_Count (Name) loop
               declare
                  Subcommand : constant String :=
                    Ada_Quality.CLI_Metadata.Subcommand_Name (Name, Sub_Index);
               begin
                  Ada.Text_IO.Put_Line
                    ("complete -c ada-quality -n '__fish_seen_subcommand_from " & Name &
                     "; and __fish_seen_subcommand_from " & Subcommand & "' -a '" &
                     Ada_Quality.CLI_Metadata.Completion_Words (Name, Subcommand) & "'");
               end;
            end loop;
         end;
      end loop;
      Ada.Text_IO.Put_Line
        ("complete -c ada-quality -l database -r -d 'Database path'; " &
         "complete -c ada-quality -l policy -r -d 'Policy path'; " &
         "complete -c ada-quality -l sign-key -r -d 'Ed25519 private key'; " &
         "complete -c ada-quality -l public-key -r -d 'Trusted Ed25519 public key'; " &
         "complete -c ada-quality -l trust-store -r -d 'Trusted key directory'; " &
         "complete -c ada-quality -l error-format -r -a 'text json'");
      Ada.Text_IO.Put_Line
        ("complete -c ada-quality -n '__fish_seen_subcommand_from check' -l jobs -r; " &
         "complete -c ada-quality -n '__fish_seen_subcommand_from scan' -l git-diff -r");
      Ada.Text_IO.Put_Line
        ("complete -c ada-quality -l project -r " &
         "-a '(ada-quality project list 2>/dev/null | awk \'{print $1}\')'; " &
         "complete -c ada-quality -l indicator -r " &
         "-a '(ada-quality indicator list 2>/dev/null | awk \'{print $1}\')'");
      Ada.Text_IO.Put_Line
        ("complete -c ada-quality -l profile -r -a '(ada-quality policy profiles 2>/dev/null)'; " &
         "complete -c ada-quality -n '__fish_seen_subcommand_from assessment' " &
         "-a '(ada-quality assessment aliases 2>/dev/null | awk \'{print $1}\')'");
   end if;
   return 0;
end Run_Completion;
