with Ada.Containers;
with Ada.Containers.Ordered_Sets;
with Ada_Quality.Finding_Identity;

package body Ada_Quality.Types is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   package Finding_Key_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => Unbounded_String,
      "<" => Ada.Strings.Unbounded."<",
      "=" => Ada.Strings.Unbounded."=");
   function Image (Id : Indicator_Id) return String is
      Raw : constant String := Indicator_Id'Image (Id);
   begin
      return Raw (Raw'First .. Raw'First + 2) & "-" & Raw (Raw'First + 4 .. Raw'Last);
   end Image;

   function Image (Status : Execution_Status) return String is
      Raw : String := Execution_Status'Image (Status);
   begin
      for C of Raw loop
         if C = '_' then
            C := '-';
         elsif C in 'A' .. 'Z' then
            C := Character'Val (Character'Pos (C) + 32);
         end if;
      end loop;
      return Raw;
   end Image;

   function Image (Status : Compliance_Status) return String is
      Raw : String := Compliance_Status'Image (Status);
   begin
      for C of Raw loop
         if C = '_' then
            C := '-';
         elsif C in 'A' .. 'Z' then
            C := Character'Val (Character'Pos (C) + 32);
         end if;
      end loop;
      return Raw;
   end Image;

   function Image (Status : Tool_Run_Status) return String is
      Raw : String := Tool_Run_Status'Image (Status);
   begin
      for C of Raw loop
         if C = '_' then
            C := '-';
         elsif C in 'A' .. 'Z' then
            C := Character'Val (Character'Pos (C) + 32);
         end if;
      end loop;
      return Raw;
   end Image;

   function Image (Value : Measurement_Value) return String is
   begin
      case Value.Kind is
         when Unavailable_Value => return To_String (Value.Reason);
         when Boolean_Value => return Boolean'Image (Value.Boolean_Data);
         when Integer_Value => return Long_Long_Integer'Image (Value.Integer_Data);
         when Decimal_Value => return Long_Long_Integer'Image (Value.Basis_Points);
         when Text_Value | Enum_Value => return To_String (Value.Text_Data);
      end case;
   end Image;

   function Is_Valid
     (Execution        : Execution_Status;
      Compliance       : Compliance_Status;
      Applicable       : Boolean;
      Measurement_Kind : Value_Kind;
      Has_Evidence     : Boolean) return Boolean
   is
   begin
      case Execution is
         when Succeeded =>
            return Compliance in Pass | Violation and then
              Measurement_Kind /= Unavailable_Value;
         when Not_Applicable =>
            return not Applicable and then Compliance = Not_Applicable
              and then Measurement_Kind = Unavailable_Value and then Has_Evidence;
         when Not_Run | Running | Blocked | Failed | Errored =>
            return Compliance = Unknown and then Measurement_Kind = Unavailable_Value;
      end case;
   end Is_Valid;

   function Is_Valid (Item : Indicator_Result) return Boolean is
     (Is_Valid
        (Item.Execution, Item.Compliance, Item.Applicable, Item.Measurement.Kind,
         Ada.Strings.Unbounded.Length (Item.Evidence) > 0));

   function Execution_Is_Terminal (Status : Execution_Status) return Boolean is
     (Status not in Not_Run | Running);

   function Fingerprint_Is_Valid (Text : String) return Boolean is
     (Text'Length > 0 and then
      (for all C of Text => C /= Character'Val (10) and then C /= Character'Val (13)));

   function Output_Digest_Is_Valid (Text : String) return Boolean is
     (Text'Length = 16 and then
      (for all C of Text => C in '0' .. '9' | 'a' .. 'f'));

   function Execution_Evidence_Is_Valid
     (Status        : Tool_Run_Status;
      Exit_Code     : Integer;
      Output_Digest : String;
      Output_Bytes  : Long_Long_Integer;
      Truncated     : Boolean) return Boolean
   is
     (Output_Digest_Is_Valid (Output_Digest) and then
      Output_Bytes >= 0 and then
      (not Truncated or else Output_Bytes > 0) and then
      (Status /= Tool_Spawn_Error or else Exit_Code = -1));

   function Execution_Is_Valid (Item : Tool_Execution) return Boolean is
     (Fingerprint_Is_Valid (To_String (Item.Tool)) and then
      Fingerprint_Is_Valid (To_String (Item.Command)) and then
      Execution_Evidence_Is_Valid
        (Item.Status, Item.Exit_Code, To_String (Item.Output_Digest),
         Item.Output_Bytes, Item.Truncated));

   function Result_Is_Publishable (Item : Indicator_Result) return Boolean is
     (Is_Valid (Item) and then Execution_Is_Terminal (Item.Execution));

   function Is_Publishable (Item : Assessment) return Boolean is
      Seen : array (Indicator_Id) of Boolean := [others => False];
      Finding_Keys : Finding_Key_Sets.Set;
   begin
      if Item.Project_Id = 0 or else Item.Status = Assessment_Running or else
        Item.Results.Length /= Ada.Containers.Count_Type (Indicator_Count'Last) or else
        not Fingerprint_Is_Valid (To_String (Item.Source_Fingerprint)) or else
        not Fingerprint_Is_Valid (To_String (Item.Policy_Fingerprint)) or else
        not Fingerprint_Is_Valid (To_String (Item.Toolchain_Fingerprint)) or else
        (for some Execution of Item.Executions => not Execution_Is_Valid (Execution))
      then
         return False;
      end if;
      for Result of Item.Results loop
         if Seen (Result.Indicator) or else not Result_Is_Publishable (Result) then
            return False;
         end if;
         Seen (Result.Indicator) := True;
         for Finding of Result.Findings loop
            if Finding.Indicator /= Result.Indicator or else
              not Ada_Quality.Finding_Identity.Matches
                (To_String (Finding.Fingerprint), Finding.Indicator, To_String (Finding.Rule),
                 To_String (Finding.Relative_Path), To_String (Finding.Message)) or else
              Finding_Keys.Contains (Finding.Fingerprint)
            then
               return False;
            end if;
            Finding_Keys.Insert (Finding.Fingerprint);
         end loop;
      end loop;
      return (for all Id in Indicator_Id => Seen (Id));
   end Is_Publishable;

   function Coverage_Passes (Covered, Total : Natural; Minimum_Basis_Points : Natural := 9_000) return Boolean is
   begin
      if Total = 0 or else Covered > Total then
         return False;
      end if;

      return Long_Long_Integer (Covered) * 10_000 >=
        Long_Long_Integer (Minimum_Basis_Points) * Long_Long_Integer (Total);
   end Coverage_Passes;
end Ada_Quality.Types;
