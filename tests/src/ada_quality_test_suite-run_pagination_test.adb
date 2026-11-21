separate (Ada_Quality_Test_Suite)
procedure Run_Pagination_Test is
   package Natural_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Natural);
   package Natural_Pages is new Ada_Quality.Pagination.Vector_Pages
     (Natural_Vectors);
   package Natural_Stream is new Ada_Quality.Pagination.Stream_Pages
     (Natural_Vectors);
   use type Natural_Vectors.Vector;

   function Values return Natural_Vectors.Vector is
      Result : Natural_Vectors.Vector;
   begin
      for Value in 1 .. 5 loop
         Result.Append (Value);
      end loop;
      return Result;
   end Values;

   procedure Test_Arguments is
      Arguments : constant Ada_Quality.CLI_Arguments.Argument_Set :=
        Ada_Quality.CLI_Arguments.Create
          ([To_Unbounded_String ("status"), To_Unbounded_String ("--only"),
            To_Unbounded_String ("stale"), To_Unbounded_String ("--json")]);
   begin
      Assert
        (Ada_Quality.CLI_Arguments.Count (Arguments) = 4 and then
         Ada_Quality.CLI_Arguments.Element (Arguments, 1) = "status" and then
         Ada_Quality.CLI_Arguments.Option (Arguments, "--only", "all") = "stale" and then
         Ada_Quality.CLI_Arguments.Option
           (Arguments, "--missing", "default") = "default" and then
         Ada_Quality.CLI_Arguments.Has_Flag (Arguments, "--json"),
         "immutable CLI arguments support isolated request parsing");
   end Test_Arguments;

   procedure Test_Vector_Pages is
      Forward_Items : Natural_Vectors.Vector := Values;
      Reverse_Items : Natural_Vectors.Vector := Values;
      All_Items     : Natural_Vectors.Vector := Values;
   begin
      Natural_Pages.Apply (Forward_Items, (Offset => 1, Limit => 2));
      Assert
        (Forward_Items.Length = 2 and then Forward_Items.First_Element = 2 and then
         Forward_Items.Last_Element = 3,
         "forward pagination applies offset before limit");
      Natural_Pages.Apply
        (Reverse_Items, (Offset => 1, Limit => 2),
         Ada_Quality.Pagination.Backward);
      Assert
        (Reverse_Items.Length = 2 and then Reverse_Items.First_Element = 3 and then
         Reverse_Items.Last_Element = 4,
         "reverse pagination retains the requested newest page");
      Natural_Pages.Apply (All_Items, (Offset => 0, Limit => 0));
      Assert (All_Items.Length = 5 and then All_Items = Values,
        "an unbounded page preserves every item");
   end Test_Vector_Pages;

   procedure Test_Stream (Direction : Ada_Quality.Pagination.Page_Direction) is
      Items : Natural_Vectors.Vector;
      Total : Natural := 0;
   begin
      if Direction = Ada_Quality.Pagination.Forward then
         for Value in 1 .. 5 loop
            Natural_Stream.Consider
              (Items, Value, Total, (Offset => 1, Limit => 2));
         end loop;
      else
         for Value in reverse 1 .. 5 loop
            Natural_Stream.Consider
              (Items, Value, Total, (Offset => 1, Limit => 2));
         end loop;
      end if;
      Natural_Stream.Complete (Items, Direction);
      Assert
        (Total = 5 and then Items.Length = 2 and then
         Items.First_Element = (if Direction = Ada_Quality.Pagination.Forward then 2 else 3) and then
         Items.Last_Element = (if Direction = Ada_Quality.Pagination.Forward then 3 else 4),
         "stream pagination counts all matches and preserves display order");
   end Test_Stream;

begin
   Test_Arguments;
   Test_Vector_Pages;
   Test_Stream (Ada_Quality.Pagination.Forward);
   Test_Stream (Ada_Quality.Pagination.Backward);

end Run_Pagination_Test;
