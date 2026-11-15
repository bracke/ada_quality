--  Ada-aware recognition of shell-oriented process execution.
private package Ada_Quality.Source_Safety is
   function Contains_Shell_Invocation (Line : String) return Boolean;
   --  Inspect one Ada source line, ignoring comments and decoding string literals.
   --  @param Line Source line.
   --  @return True for a shell executable literal or a shell-specific execution API.
end Ada_Quality.Source_Safety;
