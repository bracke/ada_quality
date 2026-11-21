separate (Ada_Quality_Test_Suite)
procedure Run_JSON_Schema_Test is
   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward
       (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Failures : Ada.Strings.Unbounded.Unbounded_String;
   Count  : Natural := 0;
begin
   for Index in Ada_Quality.Schema_Catalog.Schema_Index loop
      declare
         Name  : constant String := Ada_Quality.Schema_Catalog.Name (Index);
         Doc   : Jsonlib.Documents.Document;
         Error : Jsonlib.Errors.Error_Info;
      begin
         Count := Count + 1;
         Jsonlib.Parsers.Parse
           (Ada_Quality.Bounded_Files.Read
              (Root & "/docs/" & Name,
               Ada_Quality.Resource_Limits.Maximum_File_Bytes),
            Doc, Error);
         if Jsonlib.Errors.Failed (Error) then
            if Length (Failures) > 0 then
               Append (Failures, ", ");
            end if;
            Append (Failures, Name);
         end if;
      end;
   end loop;
   Assert
     (Count = Ada_Quality.Schema_Catalog.Schema_Count,
      "schema catalog traversal is incomplete");
   Assert
     (Length (Failures) = 0,
      "invalid JSON schemas: " & To_String (Failures));
end Run_JSON_Schema_Test;
