with Ada_Quality.Types;

--  Canonical finding-identity encoding, validation, and legacy compatibility.
package Ada_Quality.Finding_Identity is
   function Create
     (Indicator : Ada_Quality.Types.Indicator_Id;
      Rule, Path, Message : String;
      Context : String := "") return String;
   --  Build one canonical version-2 finding identity.

   function Matches
     (Key       : String;
      Indicator : Ada_Quality.Types.Indicator_Id;
      Rule, Path, Message : String) return Boolean;
   --  Test whether Key canonically identifies the supplied finding fields.
   --  Only canonical version-2 identities are accepted; legacy aliases are read-side compatibility data.

   function Legacy_Key (Key : String) return String;
   --  Return the delimiter-based compatibility alias of a valid contextual or version-2 key.
   --  Malformed and already-legacy keys are returned unchanged.
end Ada_Quality.Finding_Identity;
