separate (Ada_Quality.Reporting)
function Decode_Assessment
  (Item : Session; Run_Id : Positive; Allow_Terminal : Boolean) return Assessment_Record
is
   Run     : constant Run_Record := Evidence_Run (Item, Run_Id, Allow_Terminal);
   Group   : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
   Decoded : array (Indicator_Id) of Indicator_Result;
   Has_Result, Has_Measurement : array (Indicator_Id) of Boolean := [others => False];
   Output  : Assessment_Record;
   procedure Decode_Results is
   begin
      for Row of Group.Results loop
         declare
            Context : constant String := Context_Of ("indicator result", Row.Id);
            Id      : constant Indicator_Id := Parse_Indicator (To_String (Row.Kind), Context);
            State   : constant String := To_String (Row.State);
            Slash   : constant Natural := Ada.Strings.Fixed.Index (State, "/");
            Payload : constant String := To_String (Row.Summary);
            Value   : Indicator_Result;
            Execution  : Execution_Status;
            Compliance : Compliance_Status;
         begin
            if Has_Result (Id) then
               raise Integrity_Error with Context & ": duplicate result for " & Image (Id);
            elsif Slash = 0 or else
              not Decode_Result_State (State, Execution, Compliance)
            then
               raise Integrity_Error with Context & ": malformed result state " & State;
            end if;
            Value.Indicator := Id;
            Value.Execution := Execution;
            Value.Compliance := Compliance;
            case Run.Format is
               when Lossless_Evidence =>
                  declare
                     Payload_Value : Indicator_Result;
                  begin
                     if not Decode_Result_Payload (Payload, Payload_Value) then
                        raise Integrity_Error with Context & ": invalid or noncanonical result payload";
                     end if;
                     Value.Applicable := Payload_Value.Applicable;
                     Value.Summary := Payload_Value.Summary;
                     Value.Evidence := Payload_Value.Evidence;
                  end;
               when Legacy_Evidence =>
                  declare
                     Split : constant Natural := Ada.Strings.Fixed.Index (Payload, [LF]);
                  begin
                     if Split = 0 then
                        raise Integrity_Error with Context & ": malformed legacy result payload";
                     end if;
                     Value.Applicable := Value.Execution /= Not_Applicable;
                     Value.Summary := To_Unbounded_String (Payload (Payload'First .. Split - 1));
                     Value.Evidence := To_Unbounded_String (Payload (Split + 1 .. Payload'Last));
                  end;
            end case;
            Decoded (Id) := Value;
            Has_Result (Id) := True;
         end;
      end loop;
      for Id in Indicator_Id loop
         if not Has_Result (Id) then
            raise Integrity_Error with
              "assessment" & Positive'Image (Run_Id) & ": missing result for " & Image (Id);
         end if;
      end loop;
   end Decode_Results;

   procedure Decode_Measurements is
   begin
      for Row of Group.Measurements loop
         declare
            Context : constant String := Context_Of ("measurement", Row.Id);
            Id      : constant Indicator_Id := Parse_Indicator (To_String (Row.Kind), Context);
         begin
            if Has_Measurement (Id) then
               raise Integrity_Error with Context & ": duplicate measurement for " & Image (Id);
            end if;
            Decoded (Id).Measurement :=
              Decode_Measurement
                (Row, Context, Require_Versioned => Run.Format = Lossless_Evidence);
            Has_Measurement (Id) := True;
         end;
      end loop;
   end Decode_Measurements;

   procedure Decode_Findings is
      Seen : Finding_Key_Sets.Set;
   begin
      for Row of Group.Findings loop
         if Seen.Contains (Row.Kind) then
            raise Integrity_Error with
              Context_Of ("finding", Row.Id) & ": duplicate finding fingerprint";
         end if;
         Seen.Insert (Row.Kind);
         declare
            Value : constant Finding := Decode_Finding (Row, Run.Format);
         begin
            Decoded (Value.Indicator).Findings.Append (Value);
         end;
      end loop;
   end Decode_Findings;

   procedure Validate_Results is
   begin
      for Id in Indicator_Id loop
         if not Has_Measurement (Id) then
            raise Integrity_Error with
              "assessment" & Positive'Image (Run_Id) & ": missing measurement for " & Image (Id);
         elsif not Is_Valid (Decoded (Id)) or else
           not Execution_Is_Terminal (Decoded (Id).Execution)
         then
            raise Integrity_Error with
              "assessment" & Positive'Image (Run_Id) & ": inconsistent evidence for " & Image (Id);
         end if;
      end loop;
   end Validate_Results;
begin
   Decode_Results;
   Decode_Measurements;
   Decode_Findings;
   Validate_Results;

   Output.Run := Run;
   for Id in Indicator_Id loop
      Output.Results.Append (Decoded (Id));
   end loop;
   Output.Executions := Group.Executions;
   return Output;
end Decode_Assessment;
