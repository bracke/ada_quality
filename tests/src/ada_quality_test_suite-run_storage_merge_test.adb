separate (Ada_Quality_Test_Suite)
procedure Run_Storage_Merge_Test is
   Source_Path : constant String := Fixture_Root & "/merge_source.db";
   Divergent_Source_Path : constant String :=
     Fixture_Root & "/merge_divergent_source.db";
   Target_Path : constant String := Fixture_Root & "/merge_target.db";
   Root        : constant String :=
     Project_Tools.Files.Find_Root_Upward
       (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Store       : Ada_Quality.Storage.Store;

   procedure Remove_Fixtures is
   begin
      Project_Tools.Files.Delete_File_If_Present (Source_Path);
      Project_Tools.Files.Delete_File_If_Present (Divergent_Source_Path);
      Project_Tools.Files.Delete_File_If_Present (Target_Path);
   end Remove_Fixtures;

   procedure Create_Source
     (Path, Fingerprint : String; Coverage : Long_Long_Integer)
   is
      Source : Ada_Quality.Storage.Store;
      Value  : Assessment;
   begin
      Ada_Quality.Storage.Open (Source, Path);
      Value.Project_Id :=
        Ada_Quality.Storage.Registry.Add_Project (Source, Root);
      Value.Project_Path := To_Unbounded_String (Root);
      Value.Status := Assessment_Completed;
      Value.Source_Fingerprint := To_Unbounded_String (Fingerprint);
      Value.Policy_Fingerprint := To_Unbounded_String ("merge-policy");
      Value.Toolchain_Fingerprint := To_Unbounded_String ("merge-toolchain");
      for Indicator in Indicator_Id loop
         Value.Results.Append
           (Indicator_Result'
              (Indicator => Indicator, Execution => Succeeded,
               Compliance => Pass, Applicable => True,
               Summary => To_Unbounded_String ("merge summary"),
               Evidence => To_Unbounded_String ("lossless; evidence"),
               Measurement =>
                 (if Indicator = TST_03
                  then (Kind => Decimal_Value, Basis_Points => Coverage)
                  else (Kind => Boolean_Value, Boolean_Data => True)),
               Findings => <>));
      end loop;
      declare
         Published : constant Positive :=
           Ada_Quality.Storage.Assessments.Publish (Source, Value);
         pragma Unreferenced (Published);
      begin
         null;
      end;
      Ada_Quality.Storage.Close (Source);
   end Create_Source;

   procedure Verify_Round_Trip is
      Session : Ada_Quality.Reporting.Session;
   begin
      Ada_Quality.Reporting.Open (Session, Target_Path);
      declare
         Runs : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
           Ada_Quality.Reporting.Runs (Session);
         Decoded : constant Ada_Quality.Reporting.Assessment_Record :=
           Ada_Quality.Reporting.Read_Assessment
             (Session, Runs.First_Element.Id);
      begin
         Assert
           (Runs.Length = 2 and then
            Runs.First_Element.Format = Ada_Quality.Reporting.Lossless_Evidence,
            "merge retains the lossless child-evidence marker");
         Assert
           (Decoded.Results.Length = Indicator_Id'Pos (Indicator_Id'Last) + 1
            and then To_String (Decoded.Results.First_Element.Evidence) =
              "lossless; evidence",
            "merged assessment evidence survives a reporting round trip");
      end;
   end Verify_Round_Trip;
begin
   Remove_Fixtures;
   Create_Source (Source_Path, "merge-source", 9_250);
   Create_Source (Divergent_Source_Path, "merge-divergent", 9_500);

   Ada_Quality.Storage.Open (Store, Target_Path);
   declare
      Sources : Ada_Quality.Storage.Source_Vectors.Vector;
      Preview, Applied : Ada_Quality.Storage.Merge_Report;
      Again_Projects, Again_Assessments : Natural;
   begin
      Sources.Append (To_Unbounded_String (Source_Path));
      Sources.Append (To_Unbounded_String (Source_Path));
      Sources.Append (To_Unbounded_String (Divergent_Source_Path));
      Ada_Quality.Storage.Transfer.Merge
        (Store, Sources, Dry_Run => True, Report => Preview);
      Assert
        (Preview.Added_Projects = 1 and then
         Preview.Added_Assessments = 2 and then
         Preview.Reused_Assessments = 1 and then
         Ada_Quality.Storage.Registry.Projects (Store).Is_Empty,
         "multi-source merge preview is atomic and leaves the target unchanged");
      Ada_Quality.Storage.Transfer.Merge
        (Store, Sources, Dry_Run => False, Report => Applied);
      Ada_Quality.Storage.Transfer.Merge
        (Store, Source_Path, Again_Projects, Again_Assessments);
      Assert
        (Applied.Added_Projects = 1 and then
         Applied.Added_Assessments = 2 and then
         Applied.Reused_Assessments = 1 and then
         Again_Projects = 0 and then Again_Assessments = 0,
         "multi-source merge deduplicates exact sources and idempotent retries");
   end;
   Ada_Quality.Storage.Close (Store);

   Verify_Round_Trip;
   Remove_Fixtures;
end Run_Storage_Merge_Test;
