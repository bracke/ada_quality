with Ada.Strings.Unbounded;
with Project_Tools.Files;

--  Canonical classification of source inputs and generated project state.
package Ada_Quality.Project_Inventory is
   Excluded_Source_Directories : constant Project_Tools.Files.Name_List :=
     [Ada.Strings.Unbounded.To_Unbounded_String (".git"),
      Ada.Strings.Unbounded.To_Unbounded_String (".alire"),
      Ada.Strings.Unbounded.To_Unbounded_String ("alire_install"),
      Ada.Strings.Unbounded.To_Unbounded_String ("obj"),
      Ada.Strings.Unbounded.To_Unbounded_String ("bin"),
      Ada.Strings.Unbounded.To_Unbounded_String ("cov-obj"),
      Ada.Strings.Unbounded.To_Unbounded_String ("cov-bin"),
      Ada.Strings.Unbounded.To_Unbounded_String ("coverage"),
      Ada.Strings.Unbounded.To_Unbounded_String ("lib"),
      Ada.Strings.Unbounded.To_Unbounded_String ("gnatprove")];
   --  Directory basenames omitted from portable source traversal.

   Coverage_Evidence_Files : constant Project_Tools.Files.Name_List :=
     [Ada.Strings.Unbounded.To_Unbounded_String ("gcov-summary.txt"),
      Ada.Strings.Unbounded.To_Unbounded_String ("gcov-stability.txt")];
   --  Generated coverage files retained when staging a release assessment.

   function Is_Excluded_Source_Directory (Name : String) return Boolean;
   --  Test whether a directory contains generated or machine-local state.

   function Is_Excluded_Staging_Directory (Name : String) return Boolean;
   --  Test whether a directory is omitted entirely from an isolated workspace.

   function Is_Artifact_Directory (Name : String) return Boolean;
   --  Test whether a directory contributes to the deterministic artifact fingerprint.

   function Is_Generated_File (Root, Path : String) return Boolean;
   --  Test whether an ordinary file is generated state rather than a portable source input.

   function Is_Coverage_Driver_Stem (Stem : String) return Boolean;
   --  Identify the self-hosting coverage driver excluded from its own measurement.
end Ada_Quality.Project_Inventory;
