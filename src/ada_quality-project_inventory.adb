with Ada.Directories;
with Ada.Strings.Fixed;

package body Ada_Quality.Project_Inventory is
   use Ada.Strings.Unbounded;

   Metadata_Directories : constant Project_Tools.Files.Name_List :=
     [To_Unbounded_String (".git"), To_Unbounded_String (".alire"),
      To_Unbounded_String ("alire_install")];

   Artifact_Directories : constant Project_Tools.Files.Name_List :=
     [To_Unbounded_String ("obj"), To_Unbounded_String ("bin"),
      To_Unbounded_String ("cov-obj"), To_Unbounded_String ("cov-bin"),
      To_Unbounded_String ("coverage"), To_Unbounded_String ("dist"),
      To_Unbounded_String ("lib"),
      To_Unbounded_String ("gnatprove")];

   Generated_Suffixes : constant Project_Tools.Files.Name_List :=
     [To_Unbounded_String (".ali"), To_Unbounded_String (".o"),
      To_Unbounded_String (".bexch"), To_Unbounded_String (".gcda"),
      To_Unbounded_String (".gcno"), To_Unbounded_String (".cswi"),
      To_Unbounded_String (".stdout"), To_Unbounded_String (".stderr")];

   function Listed (Name : String; Values : Project_Tools.Files.Name_List) return Boolean is
   begin
      for Value of Values loop
         if Name = To_String (Value) then
            return True;
         end if;
      end loop;
      return False;
   end Listed;

   function Contains (Text, Pattern : String) return Boolean is
     (Ada.Strings.Fixed.Index (Text, Pattern) > 0);

   function Has_Suffix (Text, Suffix : String) return Boolean is
     (Text'Length >= Suffix'Length and then
      Text (Text'Last - Suffix'Length + 1 .. Text'Last) = Suffix);

   function Has_Generated_Suffix (Name : String) return Boolean is
   begin
      for Suffix of Generated_Suffixes loop
         if Has_Suffix (Name, To_String (Suffix)) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Generated_Suffix;

   function Relative (Root, Path : String) return String is
   begin
      if Path'Length > Root'Length + 1 and then
        Path (Path'First .. Path'First + Root'Length - 1) = Root
      then
         return Path (Path'First + Root'Length + 1 .. Path'Last);
      end if;
      return Path;
   end Relative;

   function Is_Excluded_Source_Directory (Name : String) return Boolean is
     (Listed (Name, Metadata_Directories) or else Listed (Name, Artifact_Directories));

   function Is_Excluded_Staging_Directory (Name : String) return Boolean is
     (Listed (Name, Metadata_Directories) or else
      (Name /= "coverage" and then Listed (Name, Artifact_Directories)));

   function Is_Artifact_Directory (Name : String) return Boolean is
     (Listed (Name, Artifact_Directories));

   function Is_Generated_File (Root, Path : String) return Boolean is
      Name : constant String := Ada.Directories.Simple_Name (Path);
      Rel  : constant String := "/" & Relative (Root, Path);
   begin
      if Name in "alr_test_local.log" | "alr_test_local.xml" | "settings.toml" | "build_hash_inputs" or else
        Ada.Strings.Fixed.Index (Name, ".ada-quality.db") = Name'First or else
        Has_Generated_Suffix (Name)
      then
         return True;
      elsif Contains (Rel, "/config/") and then
        (Has_Suffix (Name, "_config.ads") or else Has_Suffix (Name, "_config.gpr") or else
         Has_Suffix (Name, "_config.h"))
      then
         return True;
      else
         return Contains (Rel, "/alire/");
      end if;
   end Is_Generated_File;

   function Is_Coverage_Driver_Stem (Stem : String) return Boolean is
     (Stem = "ada_quality_coverage");
end Ada_Quality.Project_Inventory;
