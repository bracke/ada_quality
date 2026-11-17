with Ada.Calendar;
with Ada.Containers;
with Ada.Directories;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Ada_Quality.History;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality.Storage.Testing;
with Ada_Quality.Temporary_Directories;
with Ada_Quality.Types;
with Project_Tools.Files;

package body Ada_Quality_Reporting_Tests is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Ada_Quality.Types;
   use type Ada.Calendar.Time;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Reporting.Evidence_Format;
   use type Ada_Quality.History.Comparison_Selection;

   package Reporting renames Ada_Quality.Reporting;
   package Storage renames Ada_Quality.Storage;
   package Storage_Testing renames Ada_Quality.Storage.Testing;
   use type Storage_Testing.Corruption;

   type Test_Kind is
     (Missing_Database_Test, Round_Trip_Test, Lifecycle_Test, Schema_Test, Busy_Test, Legacy_Test,
      Limit_Test, History_Adapter_Test);

   type Reporting_Test (Kind : Test_Kind) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   overriding function Name (Item : Reporting_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Reporting_Test);

   type Corruption_Test (Kind : Storage_Testing.Corruption) is
     new AUnit.Simple_Test_Cases.Test_Case with null record;
   overriding function Name (Item : Corruption_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Corruption_Test);

   overriding function Name (Item : Reporting_Test) return AUnit.Message_String is
     (AUnit.Format ("REPORTING_" & Test_Kind'Image (Item.Kind)));

   overriding function Name (Item : Corruption_Test) return AUnit.Message_String is
     (AUnit.Format ("REPORTING_CORRUPTION_" & Storage_Testing.Corruption'Image (Item.Kind)));

   LF : constant Character := Character'Val (10);

   Test_Area : Ada_Quality.Temporary_Directories.Temporary_Directory;

   function Fixture_Root return String is
   begin
      if not Ada_Quality.Temporary_Directories.Is_Active (Test_Area) then
         Ada_Quality.Temporary_Directories.Create (Test_Area, "ada-quality-reporting-tests");
      end if;
      return Ada_Quality.Temporary_Directories.Path (Test_Area);
   end Fixture_Root;

   function Fixture (Name : String) return String is (Fixture_Root & "/" & Name);

   --  Remove a fixture directory and recreate it empty.
   procedure Fresh (Directory : String) is
   begin
      if Ada.Directories.Exists (Directory) then
         Ada.Directories.Delete_Tree (Directory);
      end if;
      Ada.Directories.Create_Path (Directory);
   end Fresh;

   --  Create a minimal Alire crate that the registry accepts.
   function Make_Crate (Directory, Crate : String) return String is
   begin
      Ada.Directories.Create_Path (Directory);
      Project_Tools.Files.Write_Text_File
        (Directory & "/alire.toml", "name = """ & Crate & """" & LF & "version = ""0.1.0""" & LF);
      return Ada.Directories.Full_Name (Directory);
   end Make_Crate;

   function Passing (Id : Indicator_Id) return Indicator_Result is
     (Indicator => Id, Execution => Succeeded, Compliance => Pass, Applicable => True,
      Summary => To_Unbounded_String ("passes"), Evidence => To_Unbounded_String ("evidence " & Image (Id)),
      Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>);

   --  Build a publishable assessment exercising every result shape.
   function Sample (Project_Id : Positive; Policy : String := "policy-a") return Assessment is
      Result : Assessment;
   begin
      Result.Project_Id := Project_Id;
      Result.Status := Assessment_Completed;
      Result.Source_Fingerprint := To_Unbounded_String ("source-1");
      Result.Policy_Fingerprint := To_Unbounded_String (Policy);
      Result.Toolchain_Fingerprint := To_Unbounded_String ("toolchain-1");
      for Id in Indicator_Id loop
         declare
            Item : Indicator_Result := Passing (Id);
         begin
            case Id is
               when TST_03 =>
                  Item.Measurement := (Kind => Decimal_Value, Basis_Points => 9_123);
               when SRC_01 =>
                  Item.Compliance := Violation;
                  Item.Summary := To_Unbounded_String ("line" & LF & "two \ backslash");
                  Item.Measurement := (Kind => Integer_Value, Integer_Data => 2);
                  Item.Findings.Append
                    (Finding'(Indicator => SRC_01, Rule => To_Unbounded_String ("line-length"), Level => High,
                      Message => To_Unbounded_String ("zu lang: Größe" & LF & "\n literal"),
                      Relative_Path => To_Unbounded_String ("src/ünï.adb"), Line => 42,
                      Fingerprint => To_Unbounded_String
                        (Ada_Quality.Finding_Identity.Create
                           (SRC_01, "line-length", "src/ünï.adb", "zu lang: Größe" & LF & "\n literal"))));
                  Item.Findings.Append
                    (Finding'(Indicator => SRC_01, Rule => To_Unbounded_String ("line-length"), Level => Low,
                      Message => To_Unbounded_String ("second"), Relative_Path => Null_Unbounded_String, Line => 0,
                      Fingerprint => To_Unbounded_String
                        (Ada_Quality.Finding_Identity.Create (SRC_01, "line-length", "", "second"))));
               when STR_04 =>
                  Item.Measurement := (Kind => Text_Value, Text_Data => To_Unbounded_String ("text"));
               when STR_05 =>
                  Item.Measurement := (Kind => Enum_Value, Text_Data => To_Unbounded_String ("enum"));
               when PRF_01 =>
                  Item.Execution := Not_Applicable;
                  Item.Compliance := Not_Applicable;
                  Item.Applicable := False;
                  Item.Summary := To_Unbounded_String ("not applicable");
                  Item.Measurement := (Kind => Unavailable_Value, Reason => To_Unbounded_String ("no SPARK"));
               when DOC_02 =>
                  Item.Execution := Blocked;
                  Item.Compliance := Unknown;
                  Item.Measurement := (Kind => Unavailable_Value, Reason => To_Unbounded_String ("gnatdoc missing"));
               when REL_04 =>
                  Item.Compliance := Violation;
                  Item.Measurement := (Kind => Boolean_Value, Boolean_Data => False);
               when others =>
                  null;
            end case;
            Result.Results.Append (Item);
         end;
      end loop;
      Result.Executions.Append
        (Tool_Execution'
           (Tool => To_Unbounded_String ("timeout-fixture"),
            Command => To_Unbounded_String ("sleep 2"), Status => Tool_Timed_Out,
            Exit_Code => -1, Output_Digest => To_Unbounded_String ("cbf29ce484222325"),
            Output_Bytes => 0, Truncated => False));
      Result.Executions.Append
        (Tool_Execution'
           (Tool => To_Unbounded_String ("spawn-fixture"),
            Command => To_Unbounded_String ("missing-tool"), Status => Tool_Spawn_Error,
            Exit_Code => -1, Output_Digest => To_Unbounded_String ("cbf29ce484222325"),
            Output_Bytes => 0, Truncated => False));
      return Result;
   end Sample;

   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;

   type File_State is record
      Name     : Unbounded_String;
      Content  : Unbounded_String;
      Modified : Ada.Calendar.Time;
   end record;

   type File_States is array (Positive range <>) of File_State;

   --  Capture every artifact of a database directory, byte for byte.
   function Capture (Directory : String) return File_States is
      Search : Ada.Directories.Search_Type;
      Entry_Item : Ada.Directories.Directory_Entry_Type;
      Result : File_States (1 .. 32);
      Count  : Natural := 0;
   begin
      Ada.Directories.Start_Search
        (Search, Directory, "*", [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Entry_Item);
         Count := Count + 1;
         Result (Count) :=
           (Name => To_Unbounded_String (Ada.Directories.Simple_Name (Entry_Item)),
            Content => To_Unbounded_String
              (Project_Tools.Files.Read_Raw_File (Ada.Directories.Full_Name (Entry_Item))),
            Modified => Ada.Directories.Modification_Time (Entry_Item));
      end loop;
      Ada.Directories.End_Search (Search);
      return Result (1 .. Count);
   end Capture;

   function Same (Left, Right : File_States) return Boolean is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;
      for L of Left loop
         declare
            Matched : Boolean := False;
         begin
            for R of Right loop
               if R.Name = L.Name then
                  Matched := R.Content = L.Content and then R.Modified = L.Modified;
               end if;
            end loop;
            if not Matched then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Same;

   --  Create a database with one project and return its identity.
   function Seed (Directory : String; Database_Path : String; Crate : String := "alpha") return Positive is
      Store : Storage.Store;
      Id    : Positive;
   begin
      Storage.Open (Store, Database_Path);
      Id := Storage.Add_Project (Store, Make_Crate (Directory & "/" & Crate, Crate));
      Storage.Close (Store);
      return Id;
   end Seed;

   function Publish
     (Database_Path : String; Value : Assessment; Legacy : Boolean := False) return Positive
   is
      Store : Storage.Store;
      Id    : Positive;
   begin
      Storage.Open (Store, Database_Path, Create_If_Missing => False);
      Storage_Testing.Use_Legacy_Evidence (Store, Legacy);
      Id := Storage.Publish (Store, Value);
      Storage.Close (Store);
      return Id;
   end Publish;

   procedure Expect_Error (Database_Path : String; Expected : String; Message : String) is
      Session : Reporting.Session;
      Raised  : Unbounded_String;
   begin
      begin
         Reporting.Open (Session, Database_Path);
      exception
         when Reporting.Reporting_Error => Raised := To_Unbounded_String ("reporting");
         when Reporting.Schema_Error => Raised := To_Unbounded_String ("schema");
         when Reporting.Integrity_Error => Raised := To_Unbounded_String ("integrity");
         when Reporting.Busy_Error => Raised := To_Unbounded_String ("busy");
         when Reporting.Limit_Error => Raised := To_Unbounded_String ("limit");
      end;
      Assert (To_String (Raised) = Expected, Message & " (raised '" & To_String (Raised) & "')");
      Assert (not Reporting.Is_Open (Session), Message & ": failed open leaves the session closed");
   end Expect_Error;

   procedure Expect_Read_Error (Database_Path : String; Run_Id : Positive; Expected, Message : String) is
      Session : Reporting.Session;
      Raised  : Unbounded_String;
   begin
      begin
         Reporting.Open (Session, Database_Path);
         declare
            Value : constant Reporting.Assessment_Record := Reporting.Read_Assessment (Session, Run_Id);
            pragma Unreferenced (Value);
         begin
            null;
         end;
      exception
         when Reporting.Reporting_Error => Raised := To_Unbounded_String ("reporting");
         when Reporting.Integrity_Error => Raised := To_Unbounded_String ("integrity");
      end;
      Assert (To_String (Raised) = Expected, Message & " (raised '" & To_String (Raised) & "')");
   end Expect_Read_Error;

   procedure Expect_History_Error (Database_Path : String; Run_Id : Positive; Message : String) is
      Session : Reporting.Session;
      Raised  : Boolean := False;
   begin
      begin
         Reporting.Open (Session, Database_Path);
         declare
            Value : constant Reporting.History_Evidence := Reporting.Read_History_Evidence (Session, Run_Id);
            pragma Unreferenced (Value);
         begin
            null;
         end;
      exception
         when Reporting.Integrity_Error => Raised := True;
      end;
      Assert (Raised, Message);
   end Expect_History_Error;

   procedure Expect_Trend_Error (Database_Path : String; Message : String) is
      Session : Reporting.Session;
      Raised  : Boolean := False;
   begin
      begin
         Reporting.Open (Session, Database_Path);
         declare
            Value : constant Storage.Detail_Vectors.Vector := Reporting.All_Measurements (Session);
            pragma Unreferenced (Value);
         begin
            null;
         end;
      exception
         when Reporting.Integrity_Error => Raised := True;
      end;
      Assert (Raised, Message);
   end Expect_Trend_Error;

   procedure Missing_Database is
      Directory : constant String := Fixture ("missing");
   begin
      Fresh (Directory);
      Expect_Error ("", "reporting", "an empty database path is rejected");
      Expect_Error (Directory & "/absent.db", "reporting", "a missing database is rejected");
      Assert (not Ada.Directories.Exists (Directory & "/absent.db"), "a missing database is not created");
      Expect_Error (Directory & "/no/such/dir/absent.db", "reporting", "a missing directory is rejected");
      Assert (not Ada.Directories.Exists (Directory & "/no"), "no directory is created");
      Expect_Error (Directory, "reporting", "a directory is not a database");
      declare
         Session : Reporting.Session;
         Raised  : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Reporting.Project_Vectors.Vector := Reporting.Projects (Session);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Reporting.Reporting_Error => Raised := True;
         end;
         Assert (Raised, "queries on a closed session are rejected");
      end;
   end Missing_Database;

   procedure Round_Trip is
      Directory : constant String := Fixture ("round-trip");
      Path      : constant String := Directory & "/db/quality.db";
      Project   : Positive;
      Run_Id    : Positive;
      Original  : constant Assessment := Sample (1);
      Session   : Reporting.Session;
   begin
      Fresh (Directory);
      Ada.Directories.Create_Path (Directory & "/db");
      Project := Seed (Directory, Path);
      Run_Id := Publish (Path, Sample (Project));
      declare
         Before : constant File_States := Capture (Directory & "/db");
      begin
         Reporting.Open (Session, Path);
         Assert (Reporting.Supported_Schema_Version (Session) = 3, "reporting reads schema version 3");
         Assert (Reporting.Projects (Session).Length = 1, "one project is visible");
         Assert (Reporting.Projects (Session).First_Element.Enabled, "the project is enabled");
         declare
            Runs : constant Reporting.Run_Vectors.Vector := Reporting.Runs (Session);
            Run  : constant Reporting.Run_Record := Runs.First_Element;
            Value : constant Reporting.Assessment_Record := Reporting.Read_Assessment (Session, Run_Id);
         begin
            Assert (Runs.Length = 1 and then Run.Id = Run_Id and then Run.Project_Id = Project,
              "run metadata preserves identities");
            Assert (Run.State = Assessment_Completed, "run state is completed");
            Assert (Run.Format = Reporting.Lossless_Evidence, "new publications use lossless evidence");
            Assert (Run.Started_At.Present and then Run.Finished_At.Present, "publication records timestamps");
            Assert (Reporting.Image (Run.Finished_At)'Length = 20, "timestamps render as ISO 8601 UTC");
            Assert (To_String (Run.Policy_Id) = "policy-a" and then To_String (Run.Source_Id) = "source-1" and then
              To_String (Run.Toolchain_Id) = "toolchain-1", "fingerprints are preserved");
            Assert (Value.Results.Length = 33, "a completed assessment decodes all 33 results");
            Assert
              (Reporting.Executions (Session, Run_Id).Length = 2 and then
               Reporting.Executions (Session, Run_Id) (1).Status = Tool_Timed_Out and then
               Reporting.Executions (Session, Run_Id) (2).Status = Tool_Spawn_Error and then
               To_String (Reporting.Executions (Session, Run_Id) (1).Command) = "sleep 2",
               "timed-out and spawn-error execution evidence remains reportable");
            for Index in 1 .. 33 loop
               declare
                  Got  : constant Indicator_Result := Value.Results (Index);
                  Want : constant Indicator_Result := Original.Results (Index);
               begin
                  Assert (Got.Indicator = Want.Indicator, "results are in registry order");
                  Assert (Got.Execution = Want.Execution and then Got.Compliance = Want.Compliance and then
                    Got.Applicable = Want.Applicable, Image (Got.Indicator) & " states round-trip");
                  Assert (Got.Summary = Want.Summary and then Got.Evidence = Want.Evidence,
                    Image (Got.Indicator) & " text round-trips losslessly");
                  Assert (Got.Measurement = Want.Measurement, Image (Got.Indicator) & " measurement round-trips");
                  Assert (Got.Findings.Length = Want.Findings.Length, Image (Got.Indicator) & " finding count");
                  for F in 1 .. Natural (Got.Findings.Length) loop
                     Assert (Got.Findings (F) = Want.Findings (F), Image (Got.Indicator) & " finding round-trips");
                  end loop;
               end;
            end loop;
         end;
         declare
            First_Identity : constant String := Reporting.Snapshot_Identity (Session);
            Again          : Reporting.Session;
         begin
            Reporting.Open (Again, Path);
            Assert (Reporting.Snapshot_Identity (Again) = First_Identity, "snapshot identity is deterministic");
            Assert (First_Identity'Length = 24, "snapshot identity is a 64-bit digest");
            Reporting.Close (Again);
         end;
         Reporting.Close (Session);
         Assert (not Reporting.Is_Open (Session), "close discards the snapshot");
         Assert (Same (Before, Capture (Directory & "/db")), "reporting leaves every database artifact unchanged");
      end;
      declare
         Separator : constant Character := Character'Val (16#1F#);
         First_Path : constant String := Make_Crate (Directory & "/identity-first", "first");
         Second_Path : constant String := Make_Crate (Directory & "/identity-second", "second");
         Alias_Path : constant String :=
           First_Path & Separator & "TRUE" & Separator & " 2" & Separator & " 0" & Separator &
           "ada_project" & Separator & "registered" & Separator & Second_Path;
         Alias_DB : constant String := Directory & "/identity-alias.db";
         Pair_DB  : constant String := Directory & "/identity-pair.db";
         Alias_Store, Pair_Store : Storage.Store;
         Alias_Session, Pair_Session : Reporting.Session;
         Ignored : Positive;
      begin
         Storage.Open (Alias_Store, Alias_DB);
         Ignored := Storage.Add_Project (Alias_Store, Make_Crate (Alias_Path, "alias"));
         Storage.Close (Alias_Store);
         Storage.Open (Pair_Store, Pair_DB);
         Ignored := Storage.Add_Project (Pair_Store, First_Path);
         Ignored := Storage.Add_Project (Pair_Store, Second_Path);
         Storage.Close (Pair_Store);
         Reporting.Open (Alias_Session, Alias_DB);
         Reporting.Open (Pair_Session, Pair_DB);
         Assert
           (Reporting.Snapshot_Identity (Alias_Session) /= Reporting.Snapshot_Identity (Pair_Session),
            "length-framed snapshot fields distinguish separator-aliasing row streams");
         Reporting.Close (Alias_Session);
         Reporting.Close (Pair_Session);
      end;
   end Round_Trip;

   procedure Lifecycle is
      Directory : constant String := Fixture ("lifecycle");
      Path      : constant String := Directory & "/quality.db";
      Project   : Positive;
      Completed, Interrupted, Running : Positive;
      Session   : Reporting.Session;
      Store     : Storage.Store;
   begin
      Fresh (Directory);
      Project := Seed (Directory, Path);
      Completed := Publish (Path, Sample (Project));
      Storage.Open (Store, Path, Create_If_Missing => False);
      Interrupted := Storage.Start_Assessment (Store, Project, "source-2", "policy-a");
      Storage.Interrupt_Assessment (Store, Interrupted, "operator stopped");
      Running := Storage.Start_Assessment (Store, Project, "source-3", "policy-a");
      Storage.Close (Store);

      Reporting.Open (Session, Path);
      declare
         Runs : constant Reporting.Run_Vectors.Vector := Reporting.Runs (Session, Project);
      begin
         Assert (Runs.Length = 3, "every lifecycle state is listed");
         Assert (Runs (1).Id = Completed and then Runs (2).Id = Interrupted and then Runs (3).Id = Running,
           "runs are in ascending identity order");
         Assert (Runs (2).State = Assessment_Interrupted and then Runs (3).State = Assessment_Running,
           "interrupted and running states are preserved");
         Assert (Runs (2).Finished_At.Present and then not Runs (3).Finished_At.Present,
           "terminal timestamps are recorded only for terminal runs");
         Assert (Reporting.Image (Runs (3).Finished_At) = "", "absent timestamps render as empty text");
         Assert (Runs (3).Started_At.Present, "start timestamps are recorded");
         Assert (Reporting.Runs (Session, Project + 1).Is_Empty, "project filters exclude other projects");
      end;
      Reporting.Close (Session);
      Expect_Read_Error (Path, Running, "reporting", "a running assessment cannot be read as evidence");
      Expect_Read_Error (Path, Interrupted, "reporting", "an interrupted assessment cannot be read as evidence");
      Expect_Read_Error (Path, 999, "reporting", "an unknown assessment is rejected");

      Storage.Open (Store, Path, Create_If_Missing => False);
      Storage.Remove_Project (Store, Project);
      Storage.Close (Store);
      Reporting.Open (Session, Path);
      Assert (Reporting.Projects (Session).Is_Empty, "tombstones are excluded by default");
      Assert (Reporting.Projects (Session, Include_Removed => True).First_Element.Removed,
        "tombstones are included on request");
      Reporting.Close (Session);
   end Lifecycle;

   procedure Schema is
      Directory : constant String := Fixture ("schema");
      Path      : constant String := Directory & "/quality.db";
      Store     : Storage.Store;
      Project   : Positive;
   begin
      Fresh (Directory);
      Project := Seed (Directory, Path);
      pragma Unreferenced (Project);
      Storage.Open (Store, Path, Create_If_Missing => False);
      Storage_Testing.Set_Schema_Version (Store, 2);
      Storage.Close (Store);
      declare
         Before : constant File_States := Capture (Directory);
      begin
         Expect_Error (Path, "schema", "an older schema is rejected");
         Assert (Same (Before, Capture (Directory)), "an older schema is not migrated by reporting");
      end;
      Storage.Open (Store, Path, Create_If_Missing => False);
      Assert (Storage.Schema_Version (Store) = 3, "normal storage still migrates version 2 to 3");
      Storage_Testing.Set_Schema_Version (Store, 99);
      Storage.Close (Store);
      declare
         Before : constant File_States := Capture (Directory);
      begin
         Expect_Error (Path, "schema", "a future schema is rejected");
         Assert (Same (Before, Capture (Directory)), "a future schema database is unchanged");
      end;
   end Schema;

   procedure Busy is
      Directory : constant String := Fixture ("busy");
      Path      : constant String := Directory & "/quality.db";
      Store     : Storage.Store;
      Session   : Reporting.Session;
      Project   : Positive;
   begin
      Fresh (Directory);
      Project := Seed (Directory, Path);
      Storage.Open (Store, Path, Create_If_Missing => False);
      Expect_Error (Path, "busy", "an open writer makes reporting fail with a busy error");
      Storage.Close (Store);
      Reporting.Open (Session, Path);
      Storage.Open (Store, Path, Create_If_Missing => False);
      Assert (Storage.Project (Store, Project).Enabled, "a loaded snapshot does not hold the writer lock");
      Storage.Set_Enabled (Store, Project, False);
      Storage.Close (Store);
      Assert (Reporting.Projects (Session).First_Element.Enabled, "a loaded snapshot is immutable");
      Reporting.Close (Session);
      Reporting.Open (Session, Path);
      Assert (not Reporting.Projects (Session).First_Element.Enabled, "a new snapshot sees committed writes");
      Reporting.Close (Session);
   end Busy;

   procedure Legacy is
      Directory : constant String := Fixture ("legacy");
      Path      : constant String := Directory & "/quality.db";
      Session   : Reporting.Session;
      Run_Id    : Positive;
      Value     : Assessment;
   begin
      Fresh (Directory);
      Value := Sample (Seed (Directory, Path));
      --  The schema-2 encoding splits summary and evidence at the first line feed, so legacy text is single-line.
      for Item of Value.Results loop
         if Item.Indicator = SRC_01 then
            Item.Summary := To_Unbounded_String ("legacy violation");
         end if;
      end loop;
      Run_Id := Publish (Path, Value, Legacy => True);
      Reporting.Open (Session, Path);
      declare
         Run    : constant Reporting.Run_Record := Reporting.Runs (Session).First_Element;
         Stored : constant Reporting.Assessment_Record := Reporting.Read_Assessment (Session, Run_Id);
         Src    : constant Indicator_Result := Stored.Results (Indicator_Id'Pos (SRC_01) + 1);
      begin
         Assert (Run.Format = Reporting.Legacy_Evidence, "legacy runs are identified");
         Assert (not Run.Started_At.Present and then not Run.Finished_At.Present,
           "legacy runs expose no fabricated timestamps");
         Assert (Src.Findings.Length = 2, "legacy findings are attributed through their fingerprints");
         Assert (Src.Findings (1).Line = 0 and then Length (Src.Findings (1).Relative_Path) = 0,
           "legacy findings expose no inferred location");
         Assert (To_String (Src.Findings (1).Rule) = "line-length", "legacy finding rules are preserved");
         Assert (Src.Summary = To_Unbounded_String ("legacy violation"), "legacy summaries are preserved");
         Assert (not Stored.Results (Indicator_Id'Pos (PRF_01) + 1).Applicable,
           "legacy applicability follows the not-applicable execution state");
      end;
      Reporting.Close (Session);
   end Legacy;

   procedure Corruption (Kind : Storage_Testing.Corruption) is
      Directory : constant String := Fixture ("corruption_" & Storage_Testing.Corruption'Image (Kind));
      Source    : constant String := Directory & "/source.db";
      Project   : Positive;
      Run_Id    : Positive;
   begin
      Fresh (Directory);
      Project := Seed (Directory, Source);
      Run_Id := Publish (Source, Sample (Project));
      declare
         Copy  : constant String := Directory & "/damaged.db";
         Store : Storage.Store;
      begin
         Ada.Directories.Copy_File (Source, Copy);
         if Ada.Directories.Exists (Source & ".fts") then
            Ada.Directories.Copy_File (Source & ".fts", Copy & ".fts");
         end if;
         Storage.Open (Store, Copy, Create_If_Missing => False);
         Storage_Testing.Corrupt (Store, Run_Id, Kind);
         declare
            Rejected : Boolean := False;
         begin
            begin
               Storage.Check (Store);
            exception
               when Storage.Storage_Error => Rejected := True;
            end;
            Assert (Rejected, Storage_Testing.Corruption'Image (Kind) &
              " is rejected by the database integrity command");
         end;
         Storage.Close (Store);
         Expect_Error
           (Copy, "integrity", Storage_Testing.Corruption'Image (Kind) &
            " is rejected while opening a reporting snapshot");
         case Kind is
            when Storage_Testing.Invalid_Run_State |
                 Storage_Testing.Unsupported_Evidence_Format |
                 Storage_Testing.Malformed_Run_Timestamp |
                 Storage_Testing.Incomplete_Run_Timestamps |
                 Storage_Testing.Orphaned_Run_Finish |
                 Storage_Testing.Inverted_Run_Timestamps =>
               null;
            when others =>
               Expect_Read_Error
                 (Copy, Run_Id, "integrity", Storage_Testing.Corruption'Image (Kind) & " is an integrity error");
               Expect_History_Error
                 (Copy, Run_Id,
                  Storage_Testing.Corruption'Image (Kind) & " is rejected by history evidence adapters");
               if Kind = Storage_Testing.Invalid_Measurement then
                  Expect_Trend_Error (Copy, "invalid measurement evidence is rejected by trend adapters");
               end if;
         end case;
      end;
   end Corruption;

   procedure Limit is
      Directory : constant String := Fixture ("limit");
      Path      : constant String := Directory & "/quality.db";
      Session   : Reporting.Session;
      Raised    : Boolean := False;
      Project   : Positive;
      Run_Id    : Positive;
   begin
      Fresh (Directory);
      Project := Seed (Directory, Path);
      Run_Id := Publish (Path, Sample (Project));
      pragma Unreferenced (Run_Id);
      begin
         Reporting.Open (Session, Path, (Max_Findings => 1, others => <>));
      exception
         when Reporting.Limit_Error => Raised := True;
      end;
      Assert (Raised and then not Reporting.Is_Open (Session), "exceeding a load limit is a typed failure");
      Raised := False;
      begin
         Reporting.Open (Session, Path, (Max_Results => 32, others => <>));
      exception
         when Reporting.Limit_Error => Raised := True;
      end;
      Assert (Raised and then not Reporting.Is_Open (Session),
        "result rows are independently resource bounded");
      Raised := False;
      begin
         Reporting.Open (Session, Path, (Max_Total_Rows => 1, others => <>));
      exception
         when Reporting.Limit_Error => Raised := True;
      end;
      Assert (Raised and then not Reporting.Is_Open (Session),
        "aggregate snapshot rows are resource bounded");
      Raised := False;
      begin
         Reporting.Open (Session, Path, (Max_Text_Bytes => 1, others => <>));
      exception
         when Reporting.Limit_Error => Raised := True;
      end;
      Assert (Raised and then not Reporting.Is_Open (Session),
        "aggregate persisted text is resource bounded");
      Reporting.Open (Session, Path, (Max_Findings => 2, others => <>));
      Assert (Reporting.Is_Open (Session), "a snapshot at the limit loads");
      begin
         declare
            Missing : constant Reporting.Project_Record := Reporting.Project (Session, Project + 1);
            pragma Unreferenced (Missing);
         begin
            Assert (False, "missing project lookup must fail");
         end;
      exception
         when Reporting.Reporting_Error => null;
      end;
      Reporting.Close (Session);
   end Limit;

   --  A comparison for a chosen current assessment ignores later runs: the first run has no baseline, and the
   --  second gives the latest comparison.
   procedure Chosen_Current
     (Session : Reporting.Session; Project, First, Second : Positive; Latest : Reporting.Project_Comparison)
   is
      use type Ada_Quality.History.Comparison_Status;
      Earlier : constant Reporting.Project_Comparison := Reporting.Compare_Project (Session, Project, First);
      Chosen  : constant Reporting.Project_Comparison := Reporting.Compare_Project (Session, Project, Second);
   begin
      Assert (Earlier.Selection.Status = Ada_Quality.History.No_Baseline, "an earlier current run has no baseline");
      Assert (Earlier.Changes.Is_Empty, "and no regressions");
      Assert (Chosen.Selection = Latest.Selection, "the latest chosen run selects the latest baseline");
      Assert (Chosen.Changes.Length = Latest.Changes.Length, "and finds the same regressions");
   end Chosen_Current;

   procedure History_Adapter is
      Directory : constant String := Fixture ("history");
      Path      : constant String := Directory & "/quality.db";
      Session   : Reporting.Session;
      Project   : Positive;
      First, Second : Positive;
      Changed   : Assessment;
   begin
      Fresh (Directory);
      Project := Seed (Directory, Path);
      First := Publish (Path, Sample (Project));
      Changed := Sample (Project);
      for Item of Changed.Results loop
         if Item.Indicator = DOC_01 then
            Item.Compliance := Violation;
         end if;
      end loop;
      Second := Publish (Path, Changed);
      Reporting.Open (Session, Path);
      declare
         Runs     : constant Storage.History_Vectors.Vector := Reporting.History_Items (Session, Project);
         Baseline : constant Natural := Ada_Quality.History.Baseline_Id (Runs, Second);
         Comparison : constant Reporting.Project_Comparison :=
           Reporting.Compare_Project (Session, Project);
         Selection : constant Ada_Quality.History.Comparison_Selection :=
           Reporting.Select_Project_Comparison (Session, Project);
         Trend    : constant Ada_Quality.History.Trend_Vectors.Vector :=
           Ada_Quality.History.Metric_Trend (Runs, Reporting.All_Measurements (Session, Project), TST_03);
      begin
         Assert (Baseline = First, "history adapters feed baseline selection");
         Assert (Reporting.History_Items (Session).Length = 2 and then
           Reporting.History_Items (Session, Project + 1).Is_Empty,
           "history indexes serve all, matching, and absent project selections");
         Assert (Reporting.Project (Session, Project).Id = Project and then
           Reporting.All_Results (Session).Length = 66 and then
           Reporting.All_Persisted_Measurements (Session).Length = 66 and then
           Reporting.All_Findings (Session).Length = 4 and then
           Reporting.All_Executions (Session).Length = 4 and then
           Reporting.All_Events (Session).Length = 2,
           "snapshot adapters expose projects and all bounded detail tables");
         Assert (Reporting.Executions (Session, First).Length = 2 and then
           Reporting.Events (Session, First).Length = 1,
           "per-run indexes expose execution and lifecycle rows without table scans");
         Assert
           (Selection = Comparison.Selection and then Comparison.Selection.Baseline_Id = First and then
            Comparison.Changes.Length = 1 and then
            Comparison.Changes (1).Indicator = DOC_01,
            "selection-only and full reporting comparisons share one baseline decision");
         Chosen_Current (Session, Project, First, Second, Comparison);

         Assert (Trend.Length = 2 and then Trend (1).Value = 9_123, "history adapters feed metric trends");
      end;
      Assert (Ada_Quality.Indicators.Measurement_Unit (TST_03) = "basis_points", "coverage unit is explicit");
      Assert (Ada_Quality.Indicators.Measurement_Unit (STR_01) = "none", "Boolean indicators are unitless");
      Reporting.Close (Session);
   end History_Adapter;

   overriding procedure Run_Test (Item : in out Reporting_Test) is
   begin
      Project_Tools.Files.Delete_Tree (Fixture_Root);
      Ada.Directories.Create_Path (Fixture_Root);
      case Item.Kind is
         when Missing_Database_Test => Missing_Database;
         when Round_Trip_Test => Round_Trip;
         when Lifecycle_Test => Lifecycle;
         when Schema_Test => Schema;
         when Busy_Test => Busy;
         when Legacy_Test => Legacy;
         when Limit_Test => Limit;
         when History_Adapter_Test => History_Adapter;
      end case;
      Project_Tools.Files.Delete_Tree (Fixture_Root);
   exception
      when others =>  --  AQ: audited exception boundary
         Project_Tools.Files.Delete_Tree (Fixture_Root);
         raise;
   end Run_Test;

   overriding procedure Run_Test (Item : in out Corruption_Test) is
   begin
      Project_Tools.Files.Delete_Tree (Fixture_Root);
      Ada.Directories.Create_Path (Fixture_Root);
      Corruption (Item.Kind);
      Project_Tools.Files.Delete_Tree (Fixture_Root);
   exception
      when others =>  --  AQ: audited exception boundary
         Project_Tools.Files.Delete_Tree (Fixture_Root);
         raise;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      type Test_Access is access all AUnit.Simple_Test_Cases.Test_Case'Class;
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Kind in Test_Kind loop
         Result.Add_Test (Test_Access'(new Reporting_Test (Kind)));
      end loop;
      for Kind in Storage_Testing.Corruption loop
         Result.Add_Test (Test_Access'(new Corruption_Test (Kind)));
      end loop;
      return Result;
   end Suite;
end Ada_Quality_Reporting_Tests;
