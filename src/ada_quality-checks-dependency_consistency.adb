separate (Ada_Quality.Checks)
   function Dependency_Consistency
     (Manifest_Text, Lock_Text : String) return Dependency_Evidence_Status
   is
      Declared, Resolved : Dependency_Vectors.Vector;
      Manifest_Valid : Boolean := True;
      Lock_Valid     : Boolean := True;
      Clean_Manifest : constant String := Without_TOML_Comments (Manifest_Text);
      Clean_Lock     : constant String := Without_TOML_Comments (Lock_Text);
      Manifest_Structure : constant String := TOML_Structure (Manifest_Text);
      Lock_Structure     : constant String := TOML_Structure (Lock_Text);

      function Section_End (Text : String; Start : Positive) return Natural is
         Cursor : Natural := Ada.Strings.Fixed.Index (Text, [ASCII.LF], From => Start);
      begin
         if Cursor = 0 then return Text'Last; end if;
         Cursor := Cursor + 1;
         while Cursor <= Text'Last loop
            declare
               Stop : Natural := Ada.Strings.Fixed.Index (Text, [ASCII.LF], From => Cursor);
               First : Natural := Cursor;
            begin
               if Stop = 0 then Stop := Text'Last + 1; end if;
               while First < Stop and then Text (First) in ' ' | Character'Val (9) | ASCII.CR loop
                  First := First + 1;
               end loop;
               if First < Stop and then Text (First) = '[' then return Cursor - 1; end if;
               exit when Stop > Text'Last;
               Cursor := Stop + 1;
            end;
         end loop;
         return Text'Last;
      end Section_End;

      procedure Read_Manifest_Entry (Entry_Pos : Positive) is
         Last  : constant Natural := Section_End (Clean_Manifest, Entry_Pos);
         Cursor : Natural := Ada.Strings.Fixed.Index (Clean_Manifest, [ASCII.LF], From => Entry_Pos);
      begin
         if Cursor = 0 then Manifest_Valid := False; return; end if;
         Cursor := Cursor + 1;
         while Cursor <= Last loop
            declare
               Stop : Natural := Ada.Strings.Fixed.Index (Clean_Manifest, [ASCII.LF], From => Cursor);
               Equals_At : Natural;
            begin
               if Stop = 0 or else Stop > Last + 1 then Stop := Last + 1; end if;
               Equals_At := Ada.Strings.Fixed.Index (Clean_Manifest, "=", From => Cursor);
               if Equals_At > Cursor and then Equals_At < Stop then
                  declare
                     Name : constant String := Ada.Strings.Fixed.Trim
                       (Clean_Manifest (Cursor .. Equals_At - 1), Ada.Strings.Both);
                     Parsed : constant Project_Tools.TOML.String_Parse_Result :=
                       Project_Tools.TOML.Parse_String_After
                         (Clean_Manifest (Cursor .. Stop - 1), Name, Cursor);
                  begin
                     if Name'Length = 0 or else Parsed.Status /= Project_Tools.TOML.Parsed_String or else
                       Length (Parsed.Value) = 0
                     then
                        Manifest_Valid := False;
                     else
                        Declared.Append
                          (Dependency_Entry'
                             (To_Unbounded_String (Name), Parsed.Value));
                     end if;
                  end;
               end if;
               exit when Stop > Last;
               Cursor := Stop + 1;
            end;
         end loop;
      end Read_Manifest_Entry;

      procedure Iterate_Manifest is new Project_Tools.TOML.Iterate_Section (Read_Manifest_Entry);

      procedure Read_Lock_Entry (Entry_Pos : Positive) is
         Last : constant Natural := Section_End (Clean_Lock, Entry_Pos);
         Block : constant String := Clean_Lock (Entry_Pos .. Last);
         Crate : constant Project_Tools.TOML.String_Parse_Result :=
           Project_Tools.TOML.Parse_String_After (Block, "crate", Block'First);
         Versions : constant Project_Tools.TOML.String_Parse_Result :=
           Project_Tools.TOML.Parse_String_After (Block, "versions", Block'First);
         Transitivity : constant Project_Tools.TOML.String_Parse_Result :=
           Project_Tools.TOML.Parse_String_After (Block, "transitivity", Block'First);
      begin
         if Crate.Status /= Project_Tools.TOML.Parsed_String or else
           Versions.Status /= Project_Tools.TOML.Parsed_String or else
           Transitivity.Status /= Project_Tools.TOML.Parsed_String
         then
            Lock_Valid := False;
         elsif To_String (Transitivity.Value) = "direct" then
            Resolved.Append
              (Dependency_Entry'(Crate.Value, Versions.Value));
         end if;
      end Read_Lock_Entry;

      procedure Iterate_Lock is new Project_Tools.TOML.Iterate_Section (Read_Lock_Entry);

      function Unique (Items : Dependency_Vectors.Vector) return Boolean is
      begin
         for Left in Items.First_Index .. Items.Last_Index loop
            for Right in Left + 1 .. Items.Last_Index loop
               if Items (Left).Name = Items (Right).Name then return False; end if;
            end loop;
         end loop;
         return True;
      end Unique;

      function Equivalent return Boolean is
      begin
         for Requirement of Declared loop
            if not (for some Solution of Resolved =>
              Solution.Name = Requirement.Name and then Solution.Constraint = Requirement.Constraint)
            then
               return False;
            end if;
         end loop;
         return True;
      end Equivalent;
   begin
      if Manifest_Text'Length = 0 or else Lock_Text'Length = 0 then return Dependency_Unavailable; end if;
      Iterate_Manifest (Manifest_Structure, "depends-on");
      Iterate_Lock (Lock_Structure, "solution.state");
      declare
         use type Project_Tools.TOML.Boolean_Parse_Status;
         Context_At : constant Natural := Ada.Strings.Fixed.Index (Lock_Structure, "[solution.context]");
         Solved : Project_Tools.TOML.Boolean_Parse_Result;
      begin
         if Context_At = 0 then return Dependency_Unavailable; end if;
         declare
            Last : constant Natural := Section_End (Clean_Lock, Positive (Context_At));
            Block : constant String := Clean_Lock (Context_At .. Last);
         begin
            Solved := Project_Tools.TOML.Parse_Boolean_After (Block, "solved", Block'First);
         end;
         if not Manifest_Valid or else not Lock_Valid or else
           Solved.Status /= Project_Tools.TOML.Parsed_Boolean
         then
            return Dependency_Unavailable;
         elsif not Solved.Value or else not Unique (Declared) or else not Unique (Resolved) or else not Equivalent then
            return Dependency_Inconsistent;
         else
            return Dependency_Consistent;
         end if;
      end;
   end Dependency_Consistency;
