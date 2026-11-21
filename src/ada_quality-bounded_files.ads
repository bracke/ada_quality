--  Bounded whole-file input for small textual project metadata.
package Ada_Quality.Bounded_Files is
   function Read
     (Path          : String;
      Maximum_Bytes : Positive) return String;
   --  Read at most Maximum_Bytes from Path.
   --  @exception Constraint_Error The file exceeds Maximum_Bytes.
end Ada_Quality.Bounded_Files;
