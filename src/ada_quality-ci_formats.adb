with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Ada_Quality.CI_Formats is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Jsonlib.Documents;

   function URI_Path (Text : String) return String is
      Hex    : constant String := "0123456789ABCDEF";
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for C of Text loop
         if C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' or else
           C in '-' | '.' | '_' | '~' | '/'
         then
            Append (Result, C);
         else
            Append (Result, '%');
            Append (Result, Hex (Character'Pos (C) / 16 + 1));
            Append (Result, Hex (Character'Pos (C) mod 16 + 1));
         end if;
      end loop;
      return To_String (Result);
   end URI_Path;

   function Render_SARIF
     (Findings : Finding_Vectors.Vector;
      Pretty   : Boolean := False) return String
   is
      Doc     : Document;
      Root    : constant Node := Doc.New_Object;
      Runs    : constant Node := Doc.New_Array;
      Run     : constant Node := Doc.New_Object;
      Tool    : constant Node := Doc.New_Object;
      Driver  : constant Node := Doc.New_Object;
      Results : constant Node := Doc.New_Array;
   begin
      Doc.Insert
        (Root, "$schema",
         Doc.New_String ("https://json.schemastore.org/sarif-2.1.0.json"));
      Doc.Insert (Root, "version", Doc.New_String ("2.1.0"));
      Doc.Insert (Driver, "name", Doc.New_String ("ada-quality"));
      Doc.Insert (Driver, "version", Doc.New_String (Ada_Quality.Version));
      Doc.Insert (Tool, "driver", Driver);
      Doc.Insert (Run, "tool", Tool);

      for Finding of Findings loop
            declare
               Result      : constant Node := Doc.New_Object;
               Message     : constant Node := Doc.New_Object;
               Locations   : constant Node := Doc.New_Array;
               Fingerprints : constant Node := Doc.New_Object;
               Rule_Id     : constant String :=
                 Image (Finding.Indicator) & "/" & To_String (Finding.Rule);
            begin
               Doc.Insert (Result, "ruleId", Doc.New_String (Rule_Id));
               Doc.Insert
                 (Result, "level",
                  Doc.New_String
                    ((case Finding.Level is
                        when Info => "note",
                        when Low | Medium => "warning",
                        when High | Critical => "error")));
               Doc.Insert (Message, "text", Doc.New_String (To_String (Finding.Message)));
               Doc.Insert (Result, "message", Message);
               if Length (Finding.Relative_Path) > 0 then
                  declare
                     Location : constant Node := Doc.New_Object;
                     Physical : constant Node := Doc.New_Object;
                     Artifact : constant Node := Doc.New_Object;
                     Region   : constant Node := Doc.New_Object;
                  begin
                     Doc.Insert
                       (Artifact, "uri", Doc.New_String (URI_Path (To_String (Finding.Relative_Path))));
                     Doc.Insert (Physical, "artifactLocation", Artifact);
                     if Finding.Line > 0 then
                        Doc.Insert
                          (Region, "startLine", Doc.New_Integer (Long_Long_Integer (Finding.Line)));
                        Doc.Insert (Physical, "region", Region);
                     end if;
                     Doc.Insert (Location, "physicalLocation", Physical);
                     Doc.Append (Locations, Location);
                  end;
               end if;
               Doc.Insert (Result, "locations", Locations);
               Doc.Insert
                 (Fingerprints, "adaQuality/v1",
                  Doc.New_String (To_String (Finding.Fingerprint)));
               Doc.Insert (Result, "partialFingerprints", Fingerprints);
               Doc.Append (Results, Result);
            end;
      end loop;

      Doc.Insert (Run, "results", Results);
      Doc.Append (Runs, Run);
      Doc.Insert (Root, "runs", Runs);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String
        (Doc,
         (Form => (if Pretty then Jsonlib.Serializers.Pretty else Jsonlib.Serializers.Compact),
          Indent => 2, Escape_Non_Ascii => False, Sort_Members => True));
   end Render_SARIF;

   function Render_SARIF
     (Item : Assessment;
      Pretty : Boolean := False) return String
   is
      Findings : Finding_Vectors.Vector;
   begin
      for Indicator_Result of Item.Results loop
         for Finding of Indicator_Result.Findings loop
            Findings.Append (Finding);
         end loop;
      end loop;
      return Render_SARIF (Findings, Pretty);
   end Render_SARIF;

   function XML_Escape (Text : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for C of Text loop
         case C is
            when '&' => Append (Result, "&amp;");
            when '<' => Append (Result, "&lt;");
            when '>' => Append (Result, "&gt;");
            when '"' => Append (Result, "&quot;");
            when ''' => Append (Result, "&apos;");
            when others => Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end XML_Escape;

   function Render_JUnit (Item : Assessment) return String is
      Result   : Ada.Strings.Unbounded.Unbounded_String;
      Failures : Natural := 0;
      Errors   : Natural := 0;
      Skipped  : Natural := 0;

      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
   begin
      for R of Item.Results loop
         if R.Execution = Not_Applicable or else R.Compliance = Not_Applicable then
            Skipped := Skipped + 1;
         elsif R.Execution in Blocked | Failed | Errored or else R.Compliance = Unknown then
            Errors := Errors + 1;
         elsif R.Compliance = Violation then
            Failures := Failures + 1;
         end if;
      end loop;

      Append (Result, "<?xml version=""1.0"" encoding=""UTF-8""?>" & ASCII.LF);
      Append
        (Result,
         "<testsuites tests=""" & Image (Natural (Item.Results.Length)) &
         """ failures=""" & Image (Failures) & """ errors=""" &
         Image (Errors) & """ skipped=""" & Image (Skipped) & """>" & ASCII.LF);
      Append
        (Result,
         "  <testsuite name=""ada-quality"" tests=""" &
         Image (Natural (Item.Results.Length)) & """ failures=""" &
         Image (Failures) & """ errors=""" & Image (Errors) &
         """ skipped=""" & Image (Skipped) & """>" & ASCII.LF);
      for R of Item.Results loop
         Append
           (Result,
            "    <testcase classname=""ada-quality"" name=""" & Image (R.Indicator) & """>" & ASCII.LF);
         if R.Execution = Not_Applicable or else R.Compliance = Not_Applicable then
            Append
              (Result,
               "      <skipped message=""" & XML_Escape (To_String (R.Summary)) & """/>" & ASCII.LF);
         elsif R.Execution in Blocked | Failed | Errored or else R.Compliance = Unknown then
            Append
              (Result,
               "      <error message=""" & XML_Escape (To_String (R.Summary)) & """>" &
               XML_Escape (To_String (R.Evidence)) & "</error>" & ASCII.LF);
         elsif R.Compliance = Violation then
            Append
              (Result,
               "      <failure message=""" & XML_Escape (To_String (R.Summary)) & """>" &
               XML_Escape (To_String (R.Evidence)) & "</failure>" & ASCII.LF);
         end if;
         Append (Result, "    </testcase>" & ASCII.LF);
      end loop;
      Append (Result, "  </testsuite>" & ASCII.LF & "</testsuites>" & ASCII.LF);
      return To_String (Result);
   end Render_JUnit;
end Ada_Quality.CI_Formats;
