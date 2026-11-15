with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Bounded structural validation and typed access for Alire TOML manifests.
private package Ada_Quality.Manifests is
   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   function Is_Valid (Text : String) return Boolean;
   --  Validate the complete TOML structure used by an Alire manifest.

   function Top_Level_String
     (Text, Key : String;
      Value     : out Ada.Strings.Unbounded.Unbounded_String) return Boolean;
   --  Read one nonempty top-level string.

   function Top_Level_String_Array
     (Text, Key : String;
      Values    : out String_Vectors.Vector) return Boolean;
   --  Read one nonempty top-level array containing only nonempty strings.
end Ada_Quality.Manifests;
