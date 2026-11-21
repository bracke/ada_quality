with Ada.Exceptions;
with Ada.Directories;
with Ada.Strings.Fixed;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Pointers;
with Jsonlib.Serializers;
with Project_Tools.Files;
with Regexp;

--  AQ-WAIVER: SRC-03 target=validate owner=core expires=2027-11-21 justification=json-schema-recursion
package body Ada_Quality_JSON_Contract_Testing is
   use Ada.Strings.Unbounded;
   use Jsonlib.Documents;
   use type Regexp.Compile_Status;
   use type Regexp.Match_Status;

   function Conforms_At_Depth
     (Instance, Schema : String;
      Diagnostic : out Unbounded_String;
      Schema_Directory, Schema_Reference : String;
      Initial_Reference_Depth : Natural) return Boolean;

   function Conforms
     (Instance, Schema : String;
      Diagnostic : out Unbounded_String;
      Schema_Directory : String := "";
      Schema_Reference : String := "") return Boolean
   is
   begin
      return Conforms_At_Depth
        (Instance, Schema, Diagnostic, Schema_Directory, Schema_Reference, 0);
   end Conforms;

   function Conforms_At_Depth
     (Instance, Schema : String;
      Diagnostic : out Unbounded_String;
      Schema_Directory, Schema_Reference : String;
      Initial_Reference_Depth : Natural) return Boolean
   is
      Maximum_Reference_Depth : constant Natural := 64;
      Reference_Depth : Natural := Initial_Reference_Depth;
      Instance_Document, Schema_Document : Document;
      Parse_Error : Jsonlib.Errors.Error_Info;

      procedure Fail (Message : String; Into : in out Unbounded_String) is
      begin
         if Length (Into) = 0 then
            Into := To_Unbounded_String (Message);
         end if;
      end Fail;

      function Equivalent
        (Left_Document : Document; Left : Node;
         Right_Document : Document; Right : Node) return Boolean
      is
         Left_Kind : constant Value_Kind := Kind (Left_Document, Left);
      begin
         if Left_Kind /= Kind (Right_Document, Right) then
            return False;
         end if;
         case Left_Kind is
            when Null_Value =>
               return True;
            when Boolean_Value =>
               return As_Boolean (Left_Document, Left) =
                 As_Boolean (Right_Document, Right);
            when Integer_Value =>
               return As_Integer (Left_Document, Left) =
                 As_Integer (Right_Document, Right);
            when Float_Value =>
               return Literal (Left_Document, Left) =
                 Literal (Right_Document, Right);
            when String_Value =>
               return As_String (Left_Document, Left) =
                 As_String (Right_Document, Right);
            when Array_Value =>
               if Length (Left_Document, Left) /= Length (Right_Document, Right) then
                  return False;
               end if;
               for Index in 1 .. Length (Left_Document, Left) loop
                  if not Equivalent
                    (Left_Document, Element (Left_Document, Left, Index),
                     Right_Document, Element (Right_Document, Right, Index))
                  then
                     return False;
                  end if;
               end loop;
               return True;
            when Object_Value =>
               if Length (Left_Document, Left) /= Length (Right_Document, Right) then
                  return False;
               end if;
               for Index in 1 .. Length (Left_Document, Left) loop
                  declare
                     Member_Name : constant String := Name (Left_Document, Left, Index);
                     Right_Value : constant Node := Member (Right_Document, Right, Member_Name);
                  begin
                     if not Is_Present (Right_Value) or else not Equivalent
                       (Left_Document, Element (Left_Document, Left, Index),
                        Right_Document, Right_Value)
                     then
                        return False;
                     end if;
                  end;
               end loop;
               return True;
         end case;
      end Equivalent;

      function Validate
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean;

      function Validate_Reference
        (Target, Value : Node; Path, Name : String;
         Error : in out Unbounded_String) return Boolean
      is
         Valid : Boolean;
      begin
         if Reference_Depth >= Maximum_Reference_Depth then
            Fail (Path & ": schema reference depth exceeded at " & Name, Error);
            return False;
         end if;
         Reference_Depth := Reference_Depth + 1;
         Valid := Validate (Target, Value, Path, Error);
         Reference_Depth := Reference_Depth - 1;
         return Valid;
      exception
         when others =>
            Reference_Depth := Reference_Depth - 1;
            raise;
      end Validate_Reference;

      function Validate_Keywords
        (Rule : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
      begin
         if Kind (Schema_Document, Rule) /= Object_Value then
            Fail (Path & ": schema rule is not an object", Error);
            return False;
         end if;
         for Index in 1 .. Length (Schema_Document, Rule) loop
            declare
               Keyword : constant String := Name (Schema_Document, Rule, Index);
            begin
               if Keyword not in "$schema" | "$id" | "$defs" | "$ref" | "title" | "description" |
                 "type" | "const" | "enum" | "oneOf" | "allOf" | "if" | "then" | "else" | "not" |
                 "required" | "properties" | "additionalProperties" | "items" | "minItems" |
                 "maxItems" | "uniqueItems" | "minimum" | "maximum" | "minLength" | "pattern"
               then
                  Fail (Path & ": unsupported schema keyword " & Keyword, Error);
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Validate_Keywords;

      function Type_Matches
        (Expected : String; Actual : Value_Kind) return Boolean is
        ((if Expected = "object" then Actual = Object_Value
          elsif Expected = "array" then Actual = Array_Value
          elsif Expected = "string" then Actual = String_Value
          elsif Expected = "integer" then Actual = Integer_Value
          elsif Expected = "number" then Actual in Integer_Value | Float_Value
          elsif Expected = "boolean" then Actual = Boolean_Value
          elsif Expected = "null" then Actual = Null_Value
          else False));

      function Validate_One_Of
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Alternatives : constant Node :=
           Member (Schema_Document, Rule, "oneOf");
         Matches : Natural := 0;
      begin
         if not Is_Present (Alternatives) then
            return True;
         end if;
         for Index in 1 .. Length (Schema_Document, Alternatives) loop
            declare
               Trial : Unbounded_String;
            begin
               if Validate
                 (Element (Schema_Document, Alternatives, Index),
                  Value, Path, Trial)
               then
                  Matches := Matches + 1;
               end if;
            end;
         end loop;
         if Matches /= 1 then
            Fail (Path & ": expected exactly one oneOf alternative", Error);
            return False;
         end if;
         return True;
      end Validate_One_Of;

      function Validate_Value_Set
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
      begin
         if Has_Member (Schema_Document, Rule, "const") and then
           not Equivalent
             (Instance_Document, Value, Schema_Document,
              Member (Schema_Document, Rule, "const"))
         then
            Fail (Path & ": const value differs", Error);
            return False;
         elsif Has_Member (Schema_Document, Rule, "enum") then
            declare
               Values : constant Node := Member (Schema_Document, Rule, "enum");
            begin
               for Index in 1 .. Length (Schema_Document, Values) loop
                  if Equivalent
                    (Instance_Document, Value, Schema_Document,
                     Element (Schema_Document, Values, Index))
                  then
                     return True;
                  end if;
               end loop;
               Fail (Path & ": value is outside enum", Error);
               return False;
            end;
         end if;
         return True;
      end Validate_Value_Set;

      function Validate_Required
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Required : constant Node := Member (Schema_Document, Rule, "required");
      begin
         if not Is_Present (Required) then
            return True;
         end if;
         for Index in 1 .. Length (Schema_Document, Required) loop
            declare
               Name : constant String := As_String
                 (Schema_Document, Element (Schema_Document, Required, Index));
            begin
               if not Has_Member (Instance_Document, Value, Name) then
                  Fail (Path & ": missing required member " & Name, Error);
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Validate_Required;

      function Validate_Properties
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Properties : constant Node :=
           Member (Schema_Document, Rule, "properties");
         Additional : constant Node :=
           Member (Schema_Document, Rule, "additionalProperties");
      begin
         for Index in 1 .. Length (Instance_Document, Value) loop
            declare
               Name : constant String := Jsonlib.Documents.Name
                 (Instance_Document, Value, Index);
               Property_Rule : constant Node :=
                 (if Is_Present (Properties)
                  then Member (Schema_Document, Properties, Name)
                  else No_Node);
            begin
               if Is_Present (Property_Rule) then
                  if not Validate
                    (Property_Rule,
                     Element (Instance_Document, Value, Index),
                     Path & "/" & Name, Error)
                  then
                     return False;
                  end if;
               elsif Is_Present (Additional) and then
                 Kind (Schema_Document, Additional) = Boolean_Value and then
                 not As_Boolean (Schema_Document, Additional)
               then
                  Fail (Path & ": unexpected member " & Name, Error);
                  return False;
               elsif Is_Present (Additional) and then
                 Kind (Schema_Document, Additional) = Object_Value and then
                 not Validate
                   (Additional, Element (Instance_Document, Value, Index),
                    Path & "/" & Name, Error)
               then
                  return False;
               end if;
            end;
         end loop;
         return True;
      end Validate_Properties;

      function Validate_Array_Bounds
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Count : constant Natural := Length (Instance_Document, Value);
      begin
         if Has_Member (Schema_Document, Rule, "minItems") and then
           Count < Natural
             (As_Integer
                (Schema_Document, Member (Schema_Document, Rule, "minItems")))
         then
            Fail (Path & ": fewer than minItems", Error);
            return False;
         elsif Has_Member (Schema_Document, Rule, "maxItems") and then
           Count > Natural
             (As_Integer
                (Schema_Document, Member (Schema_Document, Rule, "maxItems")))
         then
            Fail (Path & ": more than maxItems", Error);
            return False;
         end if;
         return True;
      end Validate_Array_Bounds;

      function Validate_Array_Items
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Items : constant Node := Member (Schema_Document, Rule, "items");
      begin
         if not Is_Present (Items) then
            return True;
         end if;
         for Index in 1 .. Length (Instance_Document, Value) loop
            if not Validate
              (Items, Element (Instance_Document, Value, Index),
               Path & "/" & Ada.Strings.Fixed.Trim
                 (Positive'Image (Index), Ada.Strings.Both), Error)
            then
               return False;
            end if;
         end loop;
         return True;
      end Validate_Array_Items;

      function Validate_Unique_Items
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Unique : constant Node :=
           Member (Schema_Document, Rule, "uniqueItems");
      begin
         if not Is_Present (Unique) or else
           not As_Boolean (Schema_Document, Unique)
         then
            return True;
         end if;
         for Left in 1 .. Length (Instance_Document, Value) loop
            for Right in Left + 1 .. Length (Instance_Document, Value) loop
               if Equivalent
                 (Instance_Document,
                  Element (Instance_Document, Value, Left),
                  Instance_Document,
                  Element (Instance_Document, Value, Right))
               then
                  Fail (Path & ": duplicate array item", Error);
                  return False;
               end if;
            end loop;
         end loop;
         return True;
      end Validate_Unique_Items;

      function Validate_Integer
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Number : constant Long_Long_Integer :=
           As_Integer (Instance_Document, Value);
      begin
         if Has_Member (Schema_Document, Rule, "minimum") and then
           Number < As_Integer
             (Schema_Document, Member (Schema_Document, Rule, "minimum"))
         then
            Fail (Path & ": below minimum", Error);
            return False;
         elsif Has_Member (Schema_Document, Rule, "maximum") and then
           Number > As_Integer
             (Schema_Document, Member (Schema_Document, Rule, "maximum"))
         then
            Fail (Path & ": above maximum", Error);
            return False;
         end if;
         return True;
      end Validate_Integer;

      function Validate_String
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Text : constant String := As_String (Instance_Document, Value);
      begin
         if Has_Member (Schema_Document, Rule, "minLength") and then
           Text'Length < Natural
             (As_Integer
                (Schema_Document, Member (Schema_Document, Rule, "minLength")))
         then
            Fail (Path & ": shorter than minLength", Error);
            return False;
         end if;
         if Has_Member (Schema_Document, Rule, "pattern") then
            declare
               Pattern : constant Regexp.Compile_Result := Regexp.Compile
                 (As_String
                    (Schema_Document, Member (Schema_Document, Rule, "pattern")));
            begin
               if Pattern.Status /= Regexp.Compile_Ok or else
                 Regexp.Find_First
                   (Pattern.Expression, Text).Status /= Regexp.Match_Ok
               then
                  Fail (Path & ": string does not match pattern", Error);
                  return False;
               end if;
            end;
         end if;
         return True;
      end Validate_String;

      function Validate_All_Of
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Rules : constant Node := Member (Schema_Document, Rule, "allOf");
      begin
         if not Is_Present (Rules) then
            return True;
         end if;
         for Index in 1 .. Length (Schema_Document, Rules) loop
            if not Validate
              (Element (Schema_Document, Rules, Index), Value, Path, Error)
            then
               return False;
            end if;
         end loop;
         return True;
      end Validate_All_Of;

      function Validate_Conditional
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Condition : constant Node := Member (Schema_Document, Rule, "if");
         Consequent : constant Node := Member (Schema_Document, Rule, "then");
         Alternative : constant Node := Member (Schema_Document, Rule, "else");
         Trial : Unbounded_String;
      begin
         if not Is_Present (Condition) then
            return True;
         elsif Validate (Condition, Value, Path, Trial) then
            return not Is_Present (Consequent) or else
              Validate (Consequent, Value, Path, Error);
         else
            return not Is_Present (Alternative) or else
              Validate (Alternative, Value, Path, Error);
         end if;
      end Validate_Conditional;

      function Validate_Not
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Negated : constant Node := Member (Schema_Document, Rule, "not");
         Trial : Unbounded_String;
      begin
         if Is_Present (Negated) and then Validate (Negated, Value, Path, Trial) then
            Fail (Path & ": value matches a forbidden schema", Error);
            return False;
         end if;
         return True;
      end Validate_Not;

      function Validate_Kind
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
      begin
         case Kind (Instance_Document, Value) is
            when Object_Value =>
               return Validate_Required (Rule, Value, Path, Error) and then
                 Validate_Properties (Rule, Value, Path, Error);
            when Array_Value =>
               return Validate_Array_Bounds (Rule, Value, Path, Error) and then
                 Validate_Array_Items (Rule, Value, Path, Error) and then
                 Validate_Unique_Items (Rule, Value, Path, Error);
            when Integer_Value =>
               return Validate_Integer (Rule, Value, Path, Error);
            when String_Value =>
               return Validate_String (Rule, Value, Path, Error);
            when others =>
               return True;
         end case;
      end Validate_Kind;

      function Validate
        (Rule, Value : Node; Path : String;
         Error : in out Unbounded_String) return Boolean
      is
         Reference : constant Node := Member (Schema_Document, Rule, "$ref");
         Type_Node : constant Node := Member (Schema_Document, Rule, "type");
      begin
         if not Validate_Keywords (Rule, Path, Error) then
            return False;
         elsif Is_Present (Reference) and then
           Reference_Depth >= Maximum_Reference_Depth
         then
            Fail (Path & ": schema reference depth exceeded", Error);
            return False;
         elsif Is_Present (Reference) then
            declare
               Name : constant String := As_String (Schema_Document, Reference);
               Target : constant Node :=
                 (if Name'Length > 0 and then Name (Name'First) = '#'
                  then (if Name'Length = 1 then Root (Schema_Document)
                        else Jsonlib.Pointers.Resolve
                          (Schema_Document, Name (Name'First + 1 .. Name'Last)))
                  else No_Node);
            begin
               if Is_Present (Target) then
                  if not Validate_Reference (Target, Value, Path, Name, Error) then
                     return False;
                  end if;
               elsif Name'Length > 0 and then Name (Name'First) = '#' then
                  Fail (Path & ": unresolved schema reference " & Name, Error);
                  return False;
               else
                  declare
                     Hash : constant Natural := Ada.Strings.Fixed.Index (Name, "#");
                     File_Name : constant String :=
                       (if Hash = 0 then Name else Name (Name'First .. Hash - 1));
                     Fragment : constant String :=
                       (if Hash = 0 or else Hash = Name'Last then ""
                        else Name (Hash + 1 .. Name'Last));
                  begin
                     if Schema_Directory = "" or else File_Name = "" or else
                       Ada.Directories.Simple_Name (File_Name) /= File_Name
                     then
                        Fail (Path & ": unresolved schema reference " & Name, Error);
                        return False;
                     end if;
                     declare
                        External_Path : constant String :=
                          Project_Tools.Files.Join (Schema_Directory, File_Name);
                        External_Error : Unbounded_String;
                        Valid : constant Boolean := Conforms_At_Depth
                          (Jsonlib.Serializers.To_String (Instance_Document, Value),
                           Project_Tools.Files.Read_Raw_File (External_Path),
                           External_Error, Schema_Directory, Fragment,
                           Reference_Depth + 1);
                     begin
                        if not Valid then
                           Fail
                             (Path & ": external schema " & Name & " failed: " &
                              To_String (External_Error), Error);
                           return False;
                        end if;
                     end;
                  end;
               end if;
            end;
         end if;
         if not Validate_One_Of (Rule, Value, Path, Error) then
            return False;
         elsif not Validate_All_Of (Rule, Value, Path, Error) then
            return False;
         elsif not Validate_Conditional (Rule, Value, Path, Error) then
            return False;
         elsif not Validate_Not (Rule, Value, Path, Error) then
            return False;
         elsif Is_Present (Type_Node) and then
           not Type_Matches
             (As_String (Schema_Document, Type_Node),
              Kind (Instance_Document, Value))
         then
            Fail (Path & ": value has the wrong type", Error);
            return False;
         elsif not Validate_Value_Set (Rule, Value, Path, Error) then
            return False;
         end if;
         return Validate_Kind (Rule, Value, Path, Error);
      end Validate;
   begin
      Diagnostic := Null_Unbounded_String;
      Jsonlib.Parsers.Parse (Schema, Schema_Document, Parse_Error);
      if Jsonlib.Errors.Failed (Parse_Error) then
         Diagnostic := To_Unbounded_String ("schema is not valid JSON");
         return False;
      end if;
      Jsonlib.Parsers.Parse (Instance, Instance_Document, Parse_Error);
      if Jsonlib.Errors.Failed (Parse_Error) then
         Diagnostic := To_Unbounded_String ("instance is not valid JSON");
         return False;
      end if;
      declare
         Rule : constant Node :=
           (if Schema_Reference = "" then Root (Schema_Document)
            else Jsonlib.Pointers.Resolve (Schema_Document, Schema_Reference));
      begin
         if not Is_Present (Rule) then
            Diagnostic := To_Unbounded_String
              ("unresolved schema reference #" & Schema_Reference);
            return False;
         end if;
         return Validate (Rule, Root (Instance_Document), "$", Diagnostic);
      end;
   exception
      when Error : others =>
         Diagnostic := To_Unbounded_String
           ("contract validator failed: " &
            Ada.Exceptions.Exception_Message (Error));
         return False;
   end Conforms_At_Depth;
end Ada_Quality_JSON_Contract_Testing;
