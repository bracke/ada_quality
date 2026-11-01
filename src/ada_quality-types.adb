with Ada.Containers;

package body Ada_Quality.Types is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
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

   function Is_Valid (Item : Indicator_Result) return Boolean is
   begin
      case Item.Execution is
         when Succeeded =>
            return Item.Compliance in Pass | Violation and then
              Item.Measurement.Kind /= Unavailable_Value;
         when Not_Applicable =>
            return not Item.Applicable and then Item.Compliance = Not_Applicable
              and then Item.Measurement.Kind = Unavailable_Value and then
              Ada.Strings.Unbounded.Length (Item.Evidence) > 0;
         when Not_Run | Running | Blocked | Failed | Errored =>
            return Item.Compliance = Unknown and then Item.Measurement.Kind = Unavailable_Value;
      end case;
   end Is_Valid;

   function Is_Publishable (Item : Assessment) return Boolean is
      Seen : array (Indicator_Id) of Boolean := [others => False];
   begin
      if Item.Project_Id = 0 or else Item.Status = Assessment_Running or else Item.Results.Length /= 33 then
         return False;
      end if;
      for Result of Item.Results loop
         if Seen (Result.Indicator) or else not Is_Valid (Result) then return False; end if;
         Seen (Result.Indicator) := True;
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
