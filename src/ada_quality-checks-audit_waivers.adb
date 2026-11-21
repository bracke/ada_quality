separate (Ada_Quality.Checks)
function Audit_Waivers
  (Root   : String;
   Policy : Ada_Quality.Policy.Quality_Policy) return Waiver_Audit_Vectors.Vector
is
   Metrics : constant Source_Analysis := Analyze_Source (Root, Policy);
   Files   : constant Text_Vectors.Vector := Source_Files (Root);
   Result  : Waiver_Audit_Vectors.Vector;

   function Expires_Within_Thirty_Days (Value : Review_Waiver) return Boolean is
      Text : constant String := To_String (Value.Expires);
      Stamp : Ada.Calendar.Time;
      Remaining : Duration;
      use type Ada.Calendar.Time;
   begin
      if not Value.Valid or else Text'Length /= 10 then return False; end if;
      Stamp := Ada.Calendar.Time_Of
        (Integer'Value (Text (Text'First .. Text'First + 3)),
         Integer'Value (Text (Text'First + 5 .. Text'First + 6)),
         Integer'Value (Text (Text'First + 8 .. Text'Last)));
      Remaining := Stamp - Ada.Calendar.Clock;
      return Remaining >= 0.0 and then Remaining <= 30.0 * 86_400.0;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error => return False;
   end Expires_Within_Thirty_Days;

   function Used (Path, Rule, Target : String) return Boolean is
      Prefix : constant String := Lower (Rule & " target=" & Target & " ");
   begin
      for Finding of Metrics.Findings loop
         if To_String (Finding.Relative_Path) = Path and then
           To_String (Finding.Rule) = "review-waiver" and then
           Starts_With (Lower (To_String (Finding.Message)), Prefix)
         then
            return True;
         end if;
      end loop;
      return False;
   end Used;

   procedure Inspect_Line (Path, Raw : String; Number : Positive) is
      Text : constant String := Lower (Raw);
      Comment : constant String :=
        (if Text'Length > 2 and then Text (Text'First .. Text'First + 1) = "--"
         then Ada.Strings.Fixed.Trim
           (Text (Text'First + 2 .. Text'Last), Ada.Strings.Both)
         else "");
      Marker : constant String := "aq-waiver: ";
   begin
      if not Starts_With (Comment, Marker) then
         return;
      end if;
      declare
         Payload : constant String :=
           Comment (Comment'First + Marker'Length .. Comment'Last);
         Space : constant Natural := Ada.Strings.Fixed.Index (Payload, " ");
         Target_At : constant Natural := Ada.Strings.Fixed.Index (Payload, " target=");
         Owner_At : constant Natural := Ada.Strings.Fixed.Index (Payload, " owner=");
         Rule : constant String :=
           (if Space = 0 then Payload else Payload (Payload'First .. Space - 1));
         Target : constant String :=
           (if Target_At = 0 or else Owner_At <= Target_At + 8 then ""
            else Payload (Target_At + 8 .. Owner_At - 1));
         Parsed : constant Review_Waiver := Find_Review_Waiver (Raw, Rule, Target);
         Rel : constant String := Relative (Root, Path);
         Status : constant Waiver_Status :=
           (if not Parsed.Found or else not Parsed.Valid then
              (if Parsed.Expired then Waiver_Expired else Waiver_Invalid)
            elsif Used (Rel, Rule, Target) then Waiver_Active
            else Waiver_Unused);
      begin
         Result.Append
           (Waiver_Audit_Item'
              (Rule => To_Unbounded_String (Rule), Target => Parsed.Target,
               Owner => Parsed.Owner, Expires => Parsed.Expires,
               Justification => Parsed.Justification,
               Relative_Path => To_Unbounded_String (Rel), Line => Number,
               Status => Status, Expiring => Expires_Within_Thirty_Days (Parsed)));
      end;
   end Inspect_Line;

   procedure Inspect (Path, Data : String) is
      Cursor : Natural := (if Data'Length = 0 then 0 else Data'First);
      Number : Natural := 0;
   begin
      while Cursor /= 0 and then Cursor <= Data'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index (Data, [ASCII.LF], From => Cursor);
         begin
            if Stop = 0 then Stop := Data'Last + 1; end if;
            Number := Number + 1;
            Inspect_Line
              (Path,
               Ada.Strings.Fixed.Trim
                 (Data (Cursor .. Stop - 1), Ada.Strings.Both),
               Positive (Number));
            exit when Stop > Data'Last;
            Cursor := Stop + 1;
         end;
      end loop;
   end Inspect;
begin
   for Path of Files loop
      Inspect
        (To_String (Path),
         Ada_Quality.Bounded_Files.Read (To_String (Path), Maximum_File_Bytes));
   end loop;
   return Result;
end Audit_Waivers;
