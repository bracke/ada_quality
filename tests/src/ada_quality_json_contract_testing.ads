with Ada.Strings.Unbounded;

--  Test-only validation for the JSON Schema keywords used by public contracts.
package Ada_Quality_JSON_Contract_Testing is
   function Conforms
     (Instance, Schema : String;
      Diagnostic : out Ada.Strings.Unbounded.Unbounded_String;
      Schema_Directory : String := "";
      Schema_Reference : String := "") return Boolean;
end Ada_Quality_JSON_Contract_Testing;
