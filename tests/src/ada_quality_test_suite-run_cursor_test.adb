separate (Ada_Quality_Test_Suite)
procedure Run_Cursor_Test is
   function Rejects_Cursor (Text : String) return Boolean is
   begin
      declare
         Ignored : constant Ada_Quality.CLI_Cursors.Cursor_State :=
           Ada_Quality.CLI_Cursors.Decode (Text);
         pragma Unreferenced (Ignored);
      begin
         return False;
      end;
   exception
      when Ada_Quality.CLI_Cursors.Cursor_Error => return True;
   end Rejects_Cursor;

   procedure Test_Bound_Cursor is
      Binding : constant Positive :=
        Ada_Quality.CLI_Cursors.Query_Binding ("status|only=all");
      Encoded : constant String := Ada_Quality.CLI_Cursors.Encode
        ((Version => 5, Binding => Binding, Primary => 10,
          Secondary => 4, Tertiary => 7, Offset => 0),
         Offset => 25);
      Decoded : constant Ada_Quality.CLI_Cursors.Cursor_State :=
        Ada_Quality.CLI_Cursors.Decode (Encoded);
   begin
      Assert
        (Decoded.Version = 5 and then Decoded.Binding = Binding and then
         Decoded.Primary = 10 and then Decoded.Secondary = 4 and then
         Decoded.Tertiary = 7 and then Decoded.Offset = 25 and then
         Ada_Quality.CLI_Cursors.Belongs_To (Decoded, Binding),
         "typed cursor codec preserves every versioned component");
      Assert
        (not Ada_Quality.CLI_Cursors.Belongs_To (Decoded, Binding + 1) and then
         Ada_Quality.CLI_Cursors.Query_Binding ("status|only=all") = Binding,
         "query-bound cursors reject another query and bindings are stable");
   end Test_Bound_Cursor;

   procedure Test_Legacy_Cursors is
      Empty : constant Ada_Quality.CLI_Cursors.Cursor_State :=
        Ada_Quality.CLI_Cursors.Decode ("");
      V1 : constant Ada_Quality.CLI_Cursors.Cursor_State :=
        Ada_Quality.CLI_Cursors.Decode ("v1:9");
      V2 : constant Ada_Quality.CLI_Cursors.Cursor_State :=
        Ada_Quality.CLI_Cursors.Decode ("v2:11:9");
      V3 : constant Ada_Quality.CLI_Cursors.Cursor_State :=
        Ada_Quality.CLI_Cursors.Decode ("v3:11:12:9");
      V4 : constant Ada_Quality.CLI_Cursors.Cursor_State :=
        Ada_Quality.CLI_Cursors.Decode ("v4:11:12:13:9");
   begin
      Assert
        (Empty.Version = 0 and then V1.Offset = 9 and then
         V2.Primary = 11 and then V2.Offset = 9 and then
         V3.Secondary = 12 and then V3.Offset = 9 and then
         V4.Tertiary = 13 and then V4.Offset = 9 and then
         Ada_Quality.CLI_Cursors.Belongs_To (V4, 1),
         "cursor decoding supports the complete legacy version range");
      Assert
        (Ada_Quality.CLI_Cursors.Encode (Empty, 4) = "v1:4" and then
         Ada_Quality.CLI_Cursors.Encode (V2, 4) = "v2:11:4" and then
         Ada_Quality.CLI_Cursors.Encode (V3, 4) = "v3:11:12:4" and then
         Ada_Quality.CLI_Cursors.Encode (V4, 4) = "v4:11:12:13:4",
         "cursor encoding selects the least complex lossless version");
   end Test_Legacy_Cursors;

   procedure Test_Page_Metadata is
      First_Page : constant Ada_Quality.Command_Models.Page_Info :=
        Ada_Quality.CLI_Pagination.Page_Metadata
          (Total => 5, Offset => 0, Returned => 2, Requested_Limit => 0);
      Final_Page : constant Ada_Quality.Command_Models.Page_Info :=
        Ada_Quality.CLI_Pagination.Page_Metadata
          (Total => 2, Offset => 0, Returned => 2, Requested_Limit => 10,
           Snapshot => 7);
      Bound_Page : constant Ada_Quality.Command_Models.Page_Info :=
        Ada_Quality.CLI_Pagination.Page_Metadata
          (Total => 20, Offset => 5, Returned => 5, Requested_Limit => 5,
           Snapshot => 7, Secondary_Snapshot => 8,
           Tertiary_Snapshot => 9, Binding => 10);
   begin
      Assert
        (First_Page.Present and then First_Page.Limit = 2 and then
         To_String (First_Page.Next_Cursor) = "v1:2" and then
         Final_Page.Limit = 10 and then
         Length (Final_Page.Next_Cursor) = 0 and then
         To_String (Bound_Page.Next_Cursor) = "v5:10:7:8:9:10",
         "page metadata reports effective limits and continuation state");
   end Test_Page_Metadata;
begin
   Test_Bound_Cursor;
   Test_Legacy_Cursors;
   Assert
     (Rejects_Cursor ("cursor") and then Rejects_Cursor ("v6:1") and then
      Rejects_Cursor ("v2:1") and then Rejects_Cursor ("v1:") and then
      Rejects_Cursor ("v1:x") and then Rejects_Cursor ("v1:1:2") and then
      Rejects_Cursor ("v1:999999999999999999999999999999999"),
      "malformed cursors are rejected uniformly");
   Test_Page_Metadata;
end Run_Cursor_Test;
