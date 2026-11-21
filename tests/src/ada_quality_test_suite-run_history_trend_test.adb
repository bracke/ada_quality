separate (Ada_Quality_Test_Suite)
procedure Run_History_Trend_Test is
   First_Run : constant Ada_Quality.Storage.History_Item :=
     (Id => 1, Project_Id => 1,
      Status => To_Unbounded_String ("completed"),
      Summary => Null_Unbounded_String,
      Source_Fingerprint => To_Unbounded_String ("source-a"),
      Policy_Fingerprint => To_Unbounded_String ("policy"),
      Toolchain_Fingerprint => To_Unbounded_String ("toolchain"));
   Second_Run : Ada_Quality.Storage.History_Item := First_Run;
   Third_Run  : Ada_Quality.Storage.History_Item := First_Run;
   Interrupted_Run : Ada_Quality.Storage.History_Item := First_Run;
   Runs : Ada_Quality.Storage.History_Vectors.Vector;
   Measures : Ada_Quality.Storage.Detail_Vectors.Vector;
   Third_Measure : Ada_Quality.Storage.Detail_Info;
   Trend : Ada_Quality.History.Trend_Vectors.Vector;
begin
   Second_Run.Id := 2;
   Second_Run.Source_Fingerprint := To_Unbounded_String ("source-b");
   Third_Run.Id := 3;
   Third_Run.Source_Fingerprint := To_Unbounded_String ("source-c");
   Interrupted_Run := Third_Run;
   Interrupted_Run.Id := 4;
   Interrupted_Run.Status := To_Unbounded_String ("interrupted");
   Runs.Append (First_Run);
   Runs.Append (Second_Run);
   Runs.Append (Third_Run);
   Runs.Append (Interrupted_Run);

   Measures.Append
     (Ada_Quality.Storage.Detail_Info'
      (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("DECIMAL_VALUE"),
       Summary => To_Unbounded_String (" 9600")));
   Measures.Append
     (Ada_Quality.Storage.Detail_Info'
      (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
       State => To_Unbounded_String ("DECIMAL_VALUE"),
       Summary => To_Unbounded_String (" 9200")));
   Third_Measure :=
     (Id => 3, Run_Id => 3, Kind => To_Unbounded_String ("TST-03"),
      State => To_Unbounded_String
        ("DECIMAL_VALUE;indicator_version=1;method_version=1"),
      Summary => To_Unbounded_String (" 9400"));
   Measures.Append (Third_Measure);
   Trend := Ada_Quality.History.Metric_Trend (Runs, Measures, TST_03);
   Assert
     (Trend.Length = 3 and then Trend.Last_Element.Value = 9_400,
      "an interrupted latest run does not hide completed metric history");

   Third_Measure.State := To_Unbounded_String
     ("DECIMAL_VALUE;indicator_version=2;method_version=1");
   Measures.Replace_Element (Measures.Last_Index, Third_Measure);
   Trend := Ada_Quality.History.Metric_Trend (Runs, Measures, TST_03);
   Assert
     (Trend.Length = 1 and then Trend.First_Element.Run_Id = 3,
      "metric trends isolate indicator contract versions");

   Third_Measure.State := To_Unbounded_String
     ("DECIMAL_VALUE;indicator_version=1;method_version=2");
   Measures.Replace_Element (Measures.Last_Index, Third_Measure);
   Trend := Ada_Quality.History.Metric_Trend (Runs, Measures, TST_03);
   Assert
     (Trend.Length = 1 and then Trend.First_Element.Run_Id = 3,
      "metric trends isolate measurement-method versions");

   Third_Measure.State := To_Unbounded_String ("DECIMAL_VALUE;garbage");
   Measures.Replace_Element (Measures.Last_Index, Third_Measure);
   Trend := Ada_Quality.History.Metric_Trend (Runs, Measures, TST_03);
   Assert (Trend.Is_Empty, "malformed measurement semantics cannot define a trend");
end Run_History_Trend_Test;
