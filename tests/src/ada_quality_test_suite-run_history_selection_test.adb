separate (Ada_Quality_Test_Suite)
procedure Run_History_Selection_Test is
   Runs     : Ada_Quality.Storage.History_Vectors.Vector;
   Previous : Ada_Quality.Storage.History_Item :=
     (Id => 1,
      Project_Id => 1,
      Status => To_Unbounded_String ("completed"),
      Summary => Null_Unbounded_String,
      Source_Fingerprint => To_Unbounded_String ("source-a"),
      Policy_Fingerprint => To_Unbounded_String ("policy"),
      Toolchain_Fingerprint => To_Unbounded_String ("toolchain"));
   Current  : Ada_Quality.Storage.History_Item := Previous;
begin
   Assert
     (Ada_Quality.History.Baseline_Id (Runs, 1) = 0,
      "an empty history has no baseline");
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Status =
        Ada_Quality.History.No_Assessments,
      "selection reports an empty history independently of regression tests");
   Runs.Append (Previous);
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Status =
        Ada_Quality.History.No_Baseline,
      "selection reports a lone completed assessment");

   Current.Id := 2;
   Current.Source_Fingerprint := To_Unbounded_String ("source-b");
   Runs.Append (Current);
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Status =
        Ada_Quality.History.Comparison_Available,
      "selection finds a compatible completed baseline");

   Current.Policy_Fingerprint := To_Unbounded_String ("new-policy");
   Runs.Replace_Element (Runs.Last_Index, Current);
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Policy_Changed,
      "selection explicitly reports policy changes");

   Previous.Status := To_Unbounded_String ("interrupted");
   Runs.Replace_Element (Runs.First_Index, Previous);
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Status =
        Ada_Quality.History.No_Completed_Baseline,
      "an interrupted predecessor is not a baseline");

   Previous.Status := To_Unbounded_String ("completed");
   Previous.Policy_Fingerprint := Current.Policy_Fingerprint;
   Previous.Toolchain_Fingerprint := To_Unbounded_String ("older-toolchain");
   Runs.Replace_Element (Runs.First_Index, Previous);
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Status =
        Ada_Quality.History.Toolchain_Changed,
      "selection isolates toolchain incompatibility");

   Previous.Toolchain_Fingerprint := Current.Toolchain_Fingerprint;
   Previous.Source_Fingerprint := Null_Unbounded_String;
   Runs.Replace_Element (Runs.First_Index, Previous);
   Assert
     (Ada_Quality.History.Select_Comparison (Runs).Status =
        Ada_Quality.History.No_Compatible_Baseline,
      "incomplete identity evidence blocks comparison");
end Run_History_Selection_Test;
