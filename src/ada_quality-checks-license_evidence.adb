separate (Ada_Quality.Checks)
--  AQ-WAIVER: SRC-03 target=any_known_evidence owner=aq expires=2099-12-31 justification=license-evidence-boundary
   function License_Evidence
     (Root, Manifest_Text : String) return Metadata_Evidence_Status
   is
      Declared : constant Project_Tools.TOML.String_Parse_Result :=
        Project_Tools.TOML.Parse_String_After (Manifest_Text, "licenses", Manifest_Text'First);
      Plain_Path : constant String := Project_Tools.Files.Join (Root, "LICENSE");
      Markdown_Path : constant String := Project_Tools.Files.Join (Root, "LICENSE.md");
      License_Path : constant String :=
        (if Project_Tools.Files.File_Exists (Plain_Path) then Plain_Path
         elsif Project_Tools.Files.File_Exists (Markdown_Path) then Markdown_Path else "");
      Licenses, Exceptions : Text_Vectors.Vector;
      Valid, Supported : Boolean;

      function Evidence_For (Id, Content : String) return Boolean is
         Data : constant String := Lower (Content);
      begin
         if Id = "MIT" then
            return Contains (Data, "mit license") and then Contains (Data, "permission is hereby granted");
         elsif Id = "Apache-2.0" then
            return Contains (Data, "apache license") and then Contains (Data, "version 2.0");
         elsif Id = "BSD-3-Clause" then
            return Contains (Data, "redistribution and use in source and binary forms") and then
              Contains (Data, "neither the name");
         elsif Id = "CC0-1.0" then
            return Contains (Data, "cc0 1.0 universal") or else
              (Contains (Data, "creative commons") and then Contains (Data, "cc0"));
         elsif Id = "LLVM-exception" then
            return Contains (Data, "llvm exception") or else Contains (Data, "llvm-exception");
         end if;
         return False;
      end Evidence_For;

      function Any_Known_Evidence (Content : String) return Boolean is
         Known : constant array (Positive range 1 .. 4) of Ada.Strings.Unbounded.Unbounded_String :=
           [To_Unbounded_String ("MIT"), To_Unbounded_String ("Apache-2.0"),
            To_Unbounded_String ("BSD-3-Clause"), To_Unbounded_String ("CC0-1.0")];
      begin
         for Id of Known loop
            if Evidence_For (To_String (Id), Content) then return True; end if;
         end loop;
         return False;
      end Any_Known_Evidence;
   begin
      if Declared.Status /= Project_Tools.TOML.Parsed_String or else Length (Declared.Value) = 0 or else
        License_Path'Length = 0
      then
         return Metadata_Missing;
      end if;
      Parse_SPDX (To_String (Declared.Value), Valid, Supported, Licenses, Exceptions);
      if not Valid or else not Supported then return Metadata_Unsupported; end if;
      declare
         Content : constant String := Project_Tools.Files.Read_Raw_File (License_Path);
         Declaration : constant String := Lower (To_String (Declared.Value));
         First_End : constant Natural := Ada.Strings.Fixed.Index (Content, [ASCII.LF]);
         First_Line : constant String := Lower (Ada.Strings.Fixed.Trim
           ((if First_End = 0 then Content else Content (Content'First .. First_End - 1)), Ada.Strings.Both));
         Explicit : constant Boolean := First_Line = Declaration or else
           Contains (Lower (Content), "spdx-license-identifier: " & Declaration);
         Complete : Boolean := True;
      begin
         for Id of Licenses loop
            Complete := Complete and then Evidence_For (To_String (Id), Content);
         end loop;
         for Id of Exceptions loop
            Complete := Complete and then Evidence_For (To_String (Id), Content);
         end loop;
         if Explicit or else Complete then return Metadata_Matches;
         elsif Any_Known_Evidence (Content) then return Metadata_Mismatch;
         else return Metadata_Unsupported;
         end if;
      end;
   end License_Evidence;
