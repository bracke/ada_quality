--  Typed, versioned pagination cursor codec shared by CLI handlers.
package Ada_Quality.CLI_Cursors is
   Cursor_Error : exception;

   subtype Cursor_Version is Natural range 0 .. 5;

   type Cursor_State is record
      Version   : Cursor_Version := 0;
      Binding   : Natural := 0;
      Primary   : Natural := 0;
      Secondary : Natural := 0;
      Tertiary  : Natural := 0;
      Offset    : Natural := 0;
   end record;

   function Decode (Text : String) return Cursor_State;
   --  Decode an empty or v1-v5 cursor. Empty input returns the default state.

   function Encode (State : Cursor_State; Offset : Natural) return String;
   --  Encode Offset using the most specific representation described by State.

   function Query_Binding (Query : String) return Positive;
   --  Return the stable nonzero binding used to associate v5 cursors with a query.

   function Belongs_To (State : Cursor_State; Binding : Positive) return Boolean;
   --  Legacy cursors are accepted; v5 cursors must carry Binding.
end Ada_Quality.CLI_Cursors;
