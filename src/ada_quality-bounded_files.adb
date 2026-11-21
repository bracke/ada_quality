with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

package body Ada_Quality.Bounded_Files is
   use type Ada.Streams.Stream_Element_Offset;
   function Read
     (Path          : String;
      Maximum_Bytes : Positive) return String
   is
      use Ada.Strings.Unbounded;
      File   : Ada.Streams.Stream_IO.File_Type;
      Data   : Unbounded_String;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 16_384);
      Last   : Ada.Streams.Stream_Element_Offset;

      procedure Close_Preserving_Failure is
      begin
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
      exception
         when others =>
            null;
      end Close_Preserving_Failure;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         if Last >= Buffer'First then
            declare
               Count : constant Natural := Natural (Last - Buffer'First + 1);
               Text  : String (1 .. Count);
            begin
               if Count > Maximum_Bytes or else
                 Length (Data) > Maximum_Bytes - Count
               then
                  raise Constraint_Error with "file exceeds bounded input limit: " & Path;
               end if;
               for Index in Text'Range loop
                  Text (Index) := Character'Val
                    (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index - 1)));
               end loop;
               Append (Data, Text);
            end;
         end if;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
      return To_String (Data);
   exception
      when others =>
         Close_Preserving_Failure;
         raise;
   end Read;
end Ada_Quality.Bounded_Files;
