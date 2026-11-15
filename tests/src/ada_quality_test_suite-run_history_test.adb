separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_history_test justification=one-component-fixture-matrix
procedure Run_History_Test is
begin
declare
   Baseline : constant Ada_Quality.Storage.History_Item :=
     (Id => 1, Project_Id => 1, Status => To_Unbounded_String ("completed"),
      Summary => Null_Unbounded_String, Source_Fingerprint => To_Unbounded_String ("source-a"),
      Policy_Fingerprint => To_Unbounded_String ("policy"),
      Toolchain_Fingerprint => To_Unbounded_String ("toolchain"));
   Current : Ada_Quality.Storage.History_Item := Baseline;
   Policy_Changed, Interrupted : Ada_Quality.Storage.History_Item := Baseline;
   Old_Results, New_Results : Ada_Quality.Storage.Detail_Vectors.Vector;
   Old_Measures, New_Measures : Ada_Quality.Storage.Detail_Vectors.Vector;
   Empty, Older, Renamed, Contextual : Ada_Quality.Storage.Detail_Vectors.Vector;
   Changes : Ada_Quality.History.Regression_Vectors.Vector;
   Runs : Ada_Quality.Storage.History_Vectors.Vector;
   Fingerprint : constant Ada.Strings.Unbounded.Unbounded_String :=
     To_Unbounded_String ("SRC-01:rule:file:message");

   function Has_Kind (Kind : Ada_Quality.History.Regression_Kind) return Boolean is
     (for some Change of Changes => Change.Kind = Kind);
begin
   declare
      No_Runs : Ada_Quality.Storage.History_Vectors.Vector;
   begin
      Assert (Ada_Quality.History.Baseline_Id (No_Runs, 1) = 0,
        "an empty history has no baseline");
   end;
   declare
      Items : Ada_Quality.Storage.History_Vectors.Vector;
      Previous, Latest : Ada_Quality.Storage.History_Item := Baseline;
   begin
      Assert (Ada_Quality.History.Select_Comparison (Items).Status =
        Ada_Quality.History.No_Assessments,
        "an empty history has no comparison candidate");
      Items.Append (Previous);
      Assert (Ada_Quality.History.Select_Comparison (Items).Status = Ada_Quality.History.No_Baseline,
        "one completed run has no comparison baseline");
      Latest.Id := 2;
      Latest.Source_Fingerprint := To_Unbounded_String ("source-b");
      Latest.Policy_Fingerprint := To_Unbounded_String ("policy-new");
      Items.Append (Latest);
      Assert (Ada_Quality.History.Select_Comparison (Items).Policy_Changed,
        "the immediately preceding run supports an explicit policy-change comparison");
      Previous.Status := To_Unbounded_String ("interrupted");
      Items.Replace_Element (Items.First_Index, Previous);
      Assert (Ada_Quality.History.Select_Comparison (Items).Status =
        Ada_Quality.History.No_Completed_Baseline,
        "an interrupted predecessor is not a comparison baseline");
      Previous.Status := To_Unbounded_String ("completed");
      Previous.Policy_Fingerprint := Latest.Policy_Fingerprint;
      Previous.Toolchain_Fingerprint := To_Unbounded_String ("old-toolchain");
      Items.Replace_Element (Items.First_Index, Previous);
      Assert (Ada_Quality.History.Select_Comparison (Items).Status = Ada_Quality.History.Toolchain_Changed,
        "a changed toolchain blocks comparison");
      Previous.Toolchain_Fingerprint := Latest.Toolchain_Fingerprint;
      Previous.Source_Fingerprint := Null_Unbounded_String;
      Items.Replace_Element (Items.First_Index, Previous);
      Assert (Ada_Quality.History.Select_Comparison (Items).Status =
        Ada_Quality.History.No_Compatible_Baseline,
        "incomplete identity evidence blocks comparison");
   end;
   Current.Id := 2;
   Current.Source_Fingerprint := To_Unbounded_String ("source-b");
   Policy_Changed.Id := 2;
   Policy_Changed.Source_Fingerprint := To_Unbounded_String ("source-b");
   Policy_Changed.Policy_Fingerprint := To_Unbounded_String ("policy-new");
   Interrupted.Policy_Fingerprint := To_Unbounded_String ("policy-old");
   Interrupted.Status := To_Unbounded_String ("interrupted");
   Assert (Ada_Quality.History.Policy_Comparable (Baseline, Policy_Changed),
     "completed assessments with changed policy and stable toolchain are comparable");
   Assert (not Ada_Quality.History.Policy_Comparable (Interrupted, Policy_Changed),
     "an interrupted assessment cannot become a clean policy comparison");
   Old_Results.Append
     (Ada_Quality.Storage.Detail_Info'(Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("96%")));
   New_Results.Append
     (Ada_Quality.Storage.Detail_Info'(Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("92%")));
   Old_Measures.Append
     (Ada_Quality.Storage.Detail_Info'(Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 9600")));
   New_Measures.Append
     (Ada_Quality.Storage.Detail_Info'(Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 9200")));
   Runs.Append (Baseline);
   Runs.Append (Current);
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Status =
        Ada_Quality.History.Comparison_Available and then
      Ada_Quality.History.Select_Comparison (Runs).Baseline_Id = Baseline.Id,
      "central comparison selection returns the compatible baseline");
   Assert (Ada_Quality.History.Baseline_Id (Runs, 999) = 0,
     "a missing current assessment has no baseline");
   declare
      All_Measures : Ada_Quality.Storage.Detail_Vectors.Vector := Old_Measures;
      Trend : Ada_Quality.History.Trend_Vectors.Vector;
   begin
      All_Measures.Append_Vector (New_Measures);
      Trend := Ada_Quality.History.Metric_Trend (Runs, All_Measures, TST_03);
      Assert (Trend.Length = 2 and then Trend.First_Element.Value = 9_600 and then
        Trend.Last_Element.Value = 9_200,
        "metric trends retain compatible typed measurements in run order");
   end;
   declare
      Trend_Runs : Ada_Quality.Storage.History_Vectors.Vector := Runs;
      Trend_Measures : Ada_Quality.Storage.Detail_Vectors.Vector := Old_Measures;
      Third : Ada_Quality.Storage.History_Item := Current;
      Failed : Ada_Quality.Storage.History_Item := Current;
      Third_Measure : Ada_Quality.Storage.Detail_Info := New_Measures.First_Element;
      Trend : Ada_Quality.History.Trend_Vectors.Vector;
   begin
      Trend_Measures.Append_Vector (New_Measures);
      Third.Id := 3;
      Third.Source_Fingerprint := To_Unbounded_String ("source-c");
      Failed := Third;
      Failed.Id := 4;
      Failed.Status := To_Unbounded_String ("interrupted");
      Trend_Runs.Append (Third);
      Trend_Runs.Append (Failed);
      Third_Measure.Id := 3;
      Third_Measure.Run_Id := 3;
      Third_Measure.State := To_Unbounded_String
        ("DECIMAL_VALUE;indicator_version=1;method_version=1");
      Third_Measure.Summary := To_Unbounded_String (" 9400");
      Trend_Measures.Append (Third_Measure);
      Trend := Ada_Quality.History.Metric_Trend (Trend_Runs, Trend_Measures, TST_03);
      Assert (Trend.Length = 3 and then Trend.Last_Element.Value = 9_400,
        "an interrupted latest run does not hide compatible completed metric history");
      Third_Measure.State := To_Unbounded_String
        ("DECIMAL_VALUE;indicator_version=2;method_version=1");
      Trend_Measures.Replace_Element (Trend_Measures.Last_Index, Third_Measure);
      Trend := Ada_Quality.History.Metric_Trend (Trend_Runs, Trend_Measures, TST_03);
      Assert (Trend.Length = 1 and then Trend.First_Element.Run_Id = 3,
        "metric trends do not mix different indicator contract versions");
      Third_Measure.State := To_Unbounded_String
        ("DECIMAL_VALUE;indicator_version=1;method_version=2");
      Trend_Measures.Replace_Element (Trend_Measures.Last_Index, Third_Measure);
      Trend := Ada_Quality.History.Metric_Trend (Trend_Runs, Trend_Measures, TST_03);
      Assert (Trend.Length = 1 and then Trend.First_Element.Run_Id = 3,
        "metric trends do not mix different measurement-method versions");
      Third_Measure.State := To_Unbounded_String ("DECIMAL_VALUE;garbage");
      Trend_Measures.Replace_Element (Trend_Measures.Last_Index, Third_Measure);
      Trend := Ada_Quality.History.Metric_Trend (Trend_Runs, Trend_Measures, TST_03);
      Assert (Trend.Is_Empty, "malformed measurement semantics cannot define a trend series");
   end;
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (Changes.Length = 1 and then Changes.First_Element.Kind =
     Ada_Quality.History.Worsened_Metric, "coverage drop above the gate is a metric regression");
   New_Measures.Replace_Element
     (New_Measures.First_Index,
      (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("DECIMAL_VALUE;indicator_version=2;method_version=1"),
       Summary => To_Unbounded_String (" 9200")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (not Has_Kind (Ada_Quality.History.Worsened_Metric),
     "measurements with different semantic versions are not compared as regressions");
   New_Measures.Replace_Element
     (New_Measures.First_Index,
      (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 9200")));
   Old_Results.Replace_Element
     (Old_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-02"),
         State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("5")));
   New_Results.Replace_Element
     (New_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-02"),
         State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("6")));
   Old_Measures.Replace_Element
     (Old_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-02"),
         State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String (" 5")));
   New_Measures.Replace_Element
     (New_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-02"),
         State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String (" 6")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (not Has_Kind (Ada_Quality.History.Worsened_Metric),
     "increased test registration evidence is an improvement, not a regression");
   New_Measures.Replace_Element
     (New_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-02"),
         State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String (" 4")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (Has_Kind (Ada_Quality.History.Worsened_Metric),
     "decreased test registration evidence is a metric deterioration");
   Old_Results.Replace_Element
     (Old_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("DOC-01"),
         State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("121 warnings")));
   New_Results.Replace_Element
     (New_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("DOC-01"),
         State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("122 warnings")));
   Old_Measures.Replace_Element
     (Old_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("DOC-01"),
         State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String (" 121")));
   New_Measures.Replace_Element
     (New_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("DOC-01"),
         State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String (" 122")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (not Has_Kind (Ada_Quality.History.Worsened_Metric),
     "GNATdoc diagnostic cardinality is retained as evidence but is not a trend regression");
   Old_Results.Replace_Element
     (Old_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("96%")));
   New_Results.Replace_Element
     (New_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("92%")));
   Old_Measures.Replace_Element
     (Old_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 9600")));
   New_Measures.Replace_Element
     (New_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 9200")));
   New_Results.Replace_Element
     (New_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("87%")));
   New_Measures.Replace_Element
     (New_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 8700")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (Has_Kind (Ada_Quality.History.Failed_Gate) and then
     Has_Kind (Ada_Quality.History.Worsened_Metric),
     "a coverage fall below policy is both a failed gate and worsened metric");
   New_Results.Replace_Element
     (New_Results.First_Index,
      (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("succeeded/violation-extra"), Summary => To_Unbounded_String ("87%")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (not Has_Kind (Ada_Quality.History.Failed_Gate),
     "noncanonical result states cannot create regressions");
   New_Results.Replace_Element
     (New_Results.First_Index,
      (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("87%")));
   Old_Results.Replace_Element
     (Old_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("88%")));
   Old_Measures.Replace_Element
     (Old_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 8800")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (Has_Kind (Ada_Quality.History.Worsened_Metric) and then
     not Has_Kind (Ada_Quality.History.Failed_Gate),
     "a metric can deteriorate while the indicator remains in violation");
   Old_Results.Replace_Element
     (Old_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("96%")));
   Old_Measures.Replace_Element
     (Old_Measures.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String (" 9600")));
   New_Results.Replace_Element
     (New_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
         State => To_Unbounded_String ("blocked/unknown"), Summary => To_Unbounded_String ("missing")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (Has_Kind (Ada_Quality.History.Lost_Evidence),
     "a formerly passing gate becoming blocked loses evidence");
   Current.Policy_Fingerprint := To_Unbounded_String ("new-policy");
   New_Results.Replace_Element
     (New_Results.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("87%")));
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (not Changes.Is_Empty and then Changes.First_Element.Kind =
     Ada_Quality.History.Policy_Induced_Change, "policy changes are classified separately");
   Current.Toolchain_Fingerprint := To_Unbounded_String ("different-toolchain");
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (Changes.Is_Empty, "different toolchains are not compared as quality regressions");
   Current.Toolchain_Fingerprint := Baseline.Toolchain_Fingerprint;
   declare
      Unavailable_Baseline : Ada_Quality.Storage.History_Item := Baseline;
      Unavailable_Current  : Ada_Quality.Storage.History_Item := Current;
      Unavailable_Runs     : Ada_Quality.Storage.History_Vectors.Vector;
   begin
      Unavailable_Baseline.Toolchain_Fingerprint :=
        To_Unbounded_String (Unavailable_Toolchain_Fingerprint);
      Unavailable_Current.Toolchain_Fingerprint :=
        To_Unbounded_String (Unavailable_Toolchain_Fingerprint);
      Unavailable_Runs.Append (Unavailable_Baseline);
      Unavailable_Runs.Append (Unavailable_Current);
      Assert
        (Ada_Quality.History.Select_Comparison (Unavailable_Runs).Status =
           Ada_Quality.History.No_Compatible_Baseline,
         "unavailable toolchain identities cannot establish a comparison baseline");
      Changes := Ada_Quality.History.Compare
        (Unavailable_Baseline, Unavailable_Current, Old_Results, New_Results,
         Old_Measures, New_Measures, Empty, Empty);
      Assert (Changes.Is_Empty,
        "unavailable toolchain identities cannot produce regressions");
   end;
   Current.Status := To_Unbounded_String ("interrupted");
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
   Assert (Changes.Is_Empty, "incomplete assessments are not compared as quality regressions");
   Current.Status := To_Unbounded_String ("completed");
   Older.Append
     (Ada_Quality.Storage.Detail_Info'(Id => 1, Run_Id => 1, Kind => Fingerprint,
       State => To_Unbounded_String ("HIGH"),
       Summary => To_Unbounded_String ("finding")));
   Contextual.Append
     (Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2,
         Kind => To_Unbounded_String (To_String (Fingerprint) & "@aq-context=0123456789abcdef"),
         State => To_Unbounded_String ("HIGH"), Summary => To_Unbounded_String ("finding")));
   Assert
     (Ada_Quality.History.Classify_Finding
        (Contextual.First_Element.Kind, Contextual, Older, Empty, True) =
        Ada_Quality.History.Persistent,
      "contextual finding identities retain compatibility with legacy history keys");
   declare
      Legacy : Ada_Quality.Storage.Detail_Vectors.Vector;
      Framed : Ada_Quality.Storage.Detail_Vectors.Vector;
      Framed_Key : constant Ada.Strings.Unbounded.Unbounded_String :=
        To_Unbounded_String ("SRC-01:v2:1:a1:b3:c:d:ctx:0123456789abcdef");
   begin
      Legacy.Append
        (Ada_Quality.Storage.Detail_Info'
           (Id => 4, Run_Id => 1, Kind => To_Unbounded_String ("SRC-01:a:b:c:d"),
            State => To_Unbounded_String ("HIGH"), Summary => To_Unbounded_String ("finding")));
      Framed.Append
        (Ada_Quality.Storage.Detail_Info'
           (Id => 5, Run_Id => 2, Kind => Framed_Key,
            State => To_Unbounded_String ("HIGH"), Summary => To_Unbounded_String ("finding")));
      Assert
        (Ada_Quality.History.Classify_Finding
           (Framed_Key, Framed, Legacy, Empty, True) = Ada_Quality.History.Persistent,
         "length-framed finding identities retain compatibility with legacy history keys");
   end;
   declare
      Ambiguous_Current : Ada_Quality.Storage.Detail_Vectors.Vector := Contextual;
      Second : Ada_Quality.Storage.Detail_Info := Contextual.First_Element;
      Base_Run : constant Ada_Quality.Storage.History_Item := Baseline;
      Current_Run : Ada_Quality.Storage.History_Item := Current;
      Ambiguous_Changes : Ada_Quality.History.Regression_Vectors.Vector;
   begin
      Second.Id := 3;
      Second.Kind := To_Unbounded_String (To_String (Fingerprint) & "@aq-context=fedcba9876543210");
      Ambiguous_Current.Append (Second);
      Assert
        (Ada_Quality.History.Classify_Finding
           (Contextual.First_Element.Kind, Ambiguous_Current, Older, Empty, True) =
           Ada_Quality.History.Unconfirmed,
         "one legacy identity cannot prove persistence for multiple contextual findings");
      Current_Run.Policy_Fingerprint := Base_Run.Policy_Fingerprint;
      Ambiguous_Changes := Ada_Quality.History.Compare
        (Base_Run, Current_Run, Empty, Empty, Empty, Empty, Older, Ambiguous_Current);
      Assert (Ambiguous_Changes.Length = 1,
        "legacy compatibility preserves exactly one additional regression");
      Assert (Ambiguous_Changes.First_Element.Kind = Ada_Quality.History.Introduced_Finding,
        "the unmatched contextual identity is classified as introduced");
   end;
   Renamed.Append
     (Ada_Quality.Storage.Detail_Info'
        (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("SRC-01:rule:renamed:message"),
         State => To_Unbounded_String ("HIGH"), Summary => To_Unbounded_String ("finding")));
   Assert
     (Ada_Quality.History.Classify_Finding
        (To_Unbounded_String ("SRC-01:rule:renamed:message"), Renamed, Empty, Older, True) =
        Ada_Quality.History.New_Finding,
      "the same rule and message in a different file is a distinct finding");
   Older.Replace_Element
     (Older.First_Index,
      Ada_Quality.Storage.Detail_Info'
        (Id => 1, Run_Id => 1, Kind => Fingerprint,
         State => To_Unbounded_String ("LOW"), Summary => To_Unbounded_String ("finding")));
   Current.Policy_Fingerprint := Baseline.Policy_Fingerprint;
   Changes := Ada_Quality.History.Compare
     (Baseline, Current, Empty, Empty, Empty, Empty, Older, Renamed);
   Assert (Has_Kind (Ada_Quality.History.Introduced_Finding) and then
     not Has_Kind (Ada_Quality.History.Increased_Severity),
     "a finding in another file is introduced rather than conflated with an older occurrence");
   declare
      Baseline_Set, Current_Set, Historical_Set : Ada_Quality.Storage.Detail_Vectors.Vector;
      Stable_Key : constant Ada.Strings.Unbounded.Unbounded_String :=
        To_Unbounded_String ("SRC-04:source-hygiene:alpha.adb:existing");
      Added_Key : constant Ada.Strings.Unbounded.Unbounded_String :=
        To_Unbounded_String ("SRC-04:source-hygiene:beta.adb:new");
   begin
      Baseline_Set.Append
        (Ada_Quality.Storage.Detail_Info'
           (Id => 1, Run_Id => 1, Kind => Stable_Key, State => To_Unbounded_String ("MEDIUM"),
            Summary => To_Unbounded_String ("existing finding")));
      Current_Set.Append
        (Ada_Quality.Storage.Detail_Info'
           (Id => 2, Run_Id => 2, Kind => Stable_Key, State => To_Unbounded_String ("MEDIUM"),
            Summary => To_Unbounded_String ("existing finding")));
      Current_Set.Append
        (Ada_Quality.Storage.Detail_Info'
           (Id => 3, Run_Id => 2, Kind => Added_Key, State => To_Unbounded_String ("MEDIUM"),
            Summary => To_Unbounded_String ("new finding")));
      Changes := Ada_Quality.History.Compare
        (Baseline, Current, Empty, Empty, Empty, Empty, Baseline_Set, Current_Set);
      Assert (Has_Kind (Ada_Quality.History.Introduced_Finding),
        "a new finding is a regression while its indicator remains in violation");
      Current_Set.Replace_Element
        (Current_Set.First_Index,
         (Id => 2, Run_Id => 2, Kind => Stable_Key, State => To_Unbounded_String ("NOT_HIGH"),
          Summary => To_Unbounded_String ("existing finding")));
      Changes := Ada_Quality.History.Compare
        (Baseline, Current, Empty, Empty, Empty, Empty, Baseline_Set, Current_Set);
      Assert (not Has_Kind (Ada_Quality.History.Increased_Severity),
        "noncanonical severity text cannot create a severity regression");
      Current_Set.Replace_Element
        (Current_Set.First_Index,
         (Id => 2, Run_Id => 2, Kind => Stable_Key, State => To_Unbounded_String ("MEDIUM"),
          Summary => To_Unbounded_String ("existing finding")));
      Historical_Set.Append
        (Ada_Quality.Storage.Detail_Info'
           (Id => 4, Run_Id => 1, Kind => Added_Key, State => To_Unbounded_String ("MEDIUM"),
            Summary => To_Unbounded_String ("older finding")));
      Changes := Ada_Quality.History.Compare
        (Baseline, Current, Empty, Empty, Empty, Empty, Baseline_Set, Current_Set, Historical_Set);
      Assert (Has_Kind (Ada_Quality.History.Reintroduced_Finding) and then
        not Has_Kind (Ada_Quality.History.Introduced_Finding),
        "a returning finding is distinguished from a genuinely new finding");
   end;
   Assert
     (Ada_Quality.History.Classify_Finding
        (Fingerprint, Older, Older, Empty, True) = Ada_Quality.History.Persistent,
      "a finding present in adjacent completed runs is persistent");
   declare
      Classifier : constant Ada_Quality.History.Finding_Classifier :=
        Ada_Quality.History.Build_Finding_Classifier (Older, Older, Empty);
   begin
      Assert
        (Ada_Quality.History.Classify_Finding (Classifier, Fingerprint, True) =
           Ada_Quality.History.Persistent,
         "the reusable indexed classifier preserves lifecycle semantics");
   end;
   Assert
     (Ada_Quality.History.Classify_Finding
        (Fingerprint, Empty, Older, Empty, True) = Ada_Quality.History.Resolved,
      "a finding absent from a completed run is resolved");
   Assert
     (Ada_Quality.History.Classify_Finding
        (Fingerprint, Empty, Older, Empty, False) = Ada_Quality.History.Unconfirmed,
      "an incomplete current run cannot confirm resolution");
   Assert
     (Ada_Quality.History.Classify_Finding
        (Fingerprint, Empty, Empty, Empty, True) = Ada_Quality.History.Unconfirmed,
      "an unknown finding identity remains unconfirmed");
   Assert (Ada_Quality.History.Image (Ada_Quality.History.Failed_Gate) = "failed-gate",
     "regression classifications have stable external images");
   Assert (Ada_Quality.History.Image (Ada_Quality.History.New_Finding) = "new-finding",
     "finding lifecycle classifications have stable external images");
   declare
      Missing_Changes : constant Ada_Quality.History.Regression_Vectors.Vector :=
        Ada_Quality.History.Compare
          (Baseline, Current, Empty, New_Results, Empty, New_Measures, Empty, Empty);
      Bad_Measures : Ada_Quality.Storage.Detail_Vectors.Vector := Old_Measures;
   begin
      Assert (Missing_Changes.Is_Empty, "missing baseline details cannot invent regressions");
      Bad_Measures.Replace_Element
        (Bad_Measures.First_Index,
         Ada_Quality.Storage.Detail_Info'
           (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
            State => To_Unbounded_String ("DECIMAL_VALUE"),
            Summary => To_Unbounded_String ("not-a-number")));
      Changes := Ada_Quality.History.Compare
        (Baseline, Current, Old_Results, New_Results, Bad_Measures, New_Measures, Empty, Empty);
      Assert (not Has_Kind (Ada_Quality.History.Worsened_Metric),
        "malformed historical numeric values cannot become regressions");
   end;
   declare
      Large_Runs : Ada_Quality.Storage.History_Vectors.Vector;
      Large_Measures : Ada_Quality.Storage.Detail_Vectors.Vector;
      Trend : Ada_Quality.History.Trend_Vectors.Vector;
   begin
      for J in 1 .. 1_000 loop
         Large_Runs.Append
           (Ada_Quality.Storage.History_Item'
              (Id => J, Project_Id => 1, Status => To_Unbounded_String ("completed"),
               Summary => Null_Unbounded_String,
               Source_Fingerprint => To_Unbounded_String ("source-" & Natural'Image (J)),
               Policy_Fingerprint => To_Unbounded_String ("policy"),
               Toolchain_Fingerprint => To_Unbounded_String ("toolchain")));
         Large_Measures.Append
           (Ada_Quality.Storage.Detail_Info'
              (Id => J, Run_Id => J, Kind => To_Unbounded_String ("TST-03"),
               State => To_Unbounded_String ("DECIMAL_VALUE"),
               Summary => To_Unbounded_String (Natural'Image (8_999 + J))));
      end loop;
      Trend := Ada_Quality.History.Metric_Trend (Large_Runs, Large_Measures, TST_03);
      Assert (Trend.Length = 1_000 and then Trend.Last_Element.Run_Id = 1_000,
        "large compatible histories retain deterministic trend ordering");
   end;
end;
end Run_History_Test;
