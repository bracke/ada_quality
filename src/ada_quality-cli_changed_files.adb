with Ada.Containers;
with Ada.Exceptions;
with Ada.Text_IO;
with Ada_Quality.Resource_Limits;

package body Ada_Quality.CLI_Changed_Files is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   function Read
     (Arguments : Ada_Quality.CLI_Arguments.Argument_Set)
      return String_Vectors.Vector
   is
      Result      : String_Vectors.Vector;
      Input_Bytes : Natural := 0;

      procedure Append_Path (Value : String) is
      begin
         if Value'Length = 0 then
            raise Input_Error with "changed-file lists must not contain empty paths";
         elsif Value'Length > Ada_Quality.Resource_Limits.Maximum_Path_Input_Bytes then
            raise Input_Error with "changed-file path exceeds the input limit";
         elsif Result.Length >=
           Ada.Containers.Count_Type
             (Ada_Quality.Resource_Limits.Maximum_Project_Files)
         then
            raise Input_Error with "changed-file list exceeds the project entry limit";
         elsif Input_Bytes >
           Ada_Quality.Resource_Limits.Maximum_List_Input_Bytes - Value'Length
         then
            raise Input_Error with "changed-file list exceeds the input byte limit";
         end if;
         Input_Bytes := Input_Bytes + Value'Length;
         Result.Append (To_Unbounded_String (Value));
      end Append_Path;

      procedure Read_Stream (Input : Ada.Text_IO.File_Type) is
         Buffer : String
           (1 .. Ada_Quality.Resource_Limits.Maximum_Path_Input_Bytes);
         Last : Natural;
      begin
         while not Ada.Text_IO.End_Of_File (Input) loop
            Ada.Text_IO.Get_Line (Input, Buffer, Last);
            if Last = Buffer'Last then
               if not Ada.Text_IO.End_Of_Line (Input) then
                  raise Input_Error with "changed-file path exceeds the input limit";
               end if;
               Ada.Text_IO.Skip_Line (Input);
            end if;
            if Last > 0 then
               Append_Path (Buffer (Buffer'First .. Last));
            end if;
         end loop;
      end Read_Stream;

      procedure Read_Standard_Input is
      begin
         Read_Stream (Ada.Text_IO.Standard_Input);
      end Read_Standard_Input;

      procedure Read_List (Name : String) is
         File : Ada.Text_IO.File_Type;

         procedure Close_Preserving_Failure is
         begin
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
         exception
            when others =>
               null;
         end Close_Preserving_Failure;
      begin
         if Name = "-" then
            Read_Standard_Input;
         else
            Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Name);
            Read_Stream (File);
            Ada.Text_IO.Close (File);
         end if;
      exception
         when others =>
            Close_Preserving_Failure;
            raise;
      end Read_List;
   begin
      if Ada_Quality.CLI_Arguments.Count (Arguments) > 1 then
         for Index in 1 .. Ada_Quality.CLI_Arguments.Count (Arguments) - 1 loop
            if Ada_Quality.CLI_Arguments.Element
              (Arguments, Index) = "--changed-file"
            then
               Append_Path
                 (Ada_Quality.CLI_Arguments.Element (Arguments, Index + 1));
            end if;
         end loop;
      end if;
      declare
         List : constant String :=
           Ada_Quality.CLI_Arguments.Option
             (Arguments, "--files-from", "");
      begin
         if List /= "" then
            Read_List (List);
         end if;
      end;
      return Result;
   exception
      when E : Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error |
        Ada.Text_IO.Device_Error | Ada.Text_IO.Data_Error | Ada.Text_IO.End_Error =>
         raise Input_Error with
           "cannot read changed-file list: " & Ada.Exceptions.Exception_Message (E);
   end Read;
end Ada_Quality.CLI_Changed_Files;
