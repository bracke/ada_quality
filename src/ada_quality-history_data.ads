with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Persistence-neutral read models shared by storage, reporting, and history analysis.
package Ada_Quality.History_Data is
   --  Persistence-neutral assessment metadata and detail rows for read-side consumers.
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized read-model text.

   type History_Item is record
      Id         : Positive;
      Project_Id : Positive;
      Status     : Unbounded_String;
      Summary    : Unbounded_String;
      Source_Fingerprint    : Unbounded_String;
      Policy_Fingerprint    : Unbounded_String;
      Toolchain_Fingerprint : Unbounded_String;
   end record;
   --  Immutable assessment-history metadata.
   --  @field Id Positive assessment identity.
   --  @field Project_Id Owning project identity.
   --  @field Status Persisted lifecycle state.
   --  @field Summary Stable publication summary.
   --  @field Source_Fingerprint Assessed source identity.
   --  @field Policy_Fingerprint Applied policy identity.
   --  @field Toolchain_Fingerprint Selected toolchain identity.

   package History_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => History_Item);
   --  Ordered assessment-history metadata.

   type Detail_Info is record
      Id       : Positive;
      Run_Id   : Positive;
      Kind     : Unbounded_String;
      State    : Unbounded_String;
      Summary  : Unbounded_String;
   end record;
   --  Immutable read-model row used by history comparisons and archive rendering.
   --  @field Id Positive row identity.
   --  @field Run_Id Owning assessment identity.
   --  @field Kind Stable detail identity or category.
   --  @field State Stable typed state.
   --  @field Summary Persisted evidence payload.

   package Detail_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Detail_Info);
   --  Ordered read-model detail rows.
end Ada_Quality.History_Data;
