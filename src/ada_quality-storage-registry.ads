--  Project-registry capability for an open storage handle.
package Ada_Quality.Storage.Registry is
   function Add_Project (Item : in out Store; Path : String) return Positive;
   --  Validate and register an existing nonsymlink Alire crate.
   --  @param Item Open writable store.
   --  @param Path Project root to register.
   --  @return Stable project identity.

   function Projects
     (Item : in out Store; Include_Removed : Boolean := False)
      return Project_Vectors.Vector;
   --  Return registry rows in deterministic identity order.
   --  @param Item Open store.
   --  @param Include_Removed Whether tombstoned rows are included.

   function Project (Item : in out Store; Id : Positive) return Project_Info;
   --  Return one registry row, or raise Storage_Error when it is absent.

   procedure Set_Enabled
     (Item : in out Store; Id : Positive; Enabled : Boolean);
   --  Change whether bulk assessments include the project.

   procedure Remove_Project (Item : in out Store; Id : Positive);
   --  Tombstone a project while retaining its assessment history.

   procedure Relocate_Project
     (Item : in out Store; Id : Positive; Path : String);
   --  Replace a project's validated root without changing its identity.

   procedure Add_Tag (Item : in out Store; Id : Positive; Name : String);
   --  Add one canonical tag; an existing tag is accepted.

   procedure Remove_Tag (Item : in out Store; Id : Positive; Name : String);
   --  Remove one canonical tag; an absent tag is accepted.

   function Has_Tag (Project : Project_Info; Name : String) return Boolean;
   --  Return whether Project has exactly Name.

   function Is_Tag_Name (Name : String) return Boolean;
   --  Return whether Name is a canonical project tag.
end Ada_Quality.Storage.Registry;
