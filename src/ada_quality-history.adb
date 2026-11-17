with Ada.Containers;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Indicators;
with Ada_Quality.Persistence;

package body Ada_Quality.History is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Indicators;
   use Ada_Quality.History_Data;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;

   package Detail_Key_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Unbounded_String, Element_Type => Detail_Info);
   package Run_Measurement_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Detail_Info);

   function Legacy_Finding_Key (Key : Unbounded_String) return Unbounded_String is
     (To_Unbounded_String (Ada_Quality.Finding_Identity.Legacy_Key (To_String (Key))));

   function Finding_Indicator (Key : Unbounded_String; Id : out Indicator_Id) return Boolean is
      Text  : constant String := To_String (Key);
      Colon : constant Natural := Ada.Strings.Fixed.Index (Text, ":");
   begin
      if Colon <= 1 then
         Id := STR_01;
         return False;
      end if;
      return Ada_Quality.Indicators.Parse_Canonical (Text (Text'First .. Colon - 1), Id);
   end Finding_Indicator;

   function Legacy_Match_Available
     (Baseline : Detail_Key_Maps.Map;
      Consumed : Finding_Key_Sets.Set;
      Current, Legacy : Unbounded_String) return Boolean is
     (Legacy /= Current and then Baseline.Contains (Legacy) and then not Consumed.Contains (Legacy));

   function Toolchain_Is_Available (Value : Unbounded_String) return Boolean is
     (Length (Value) > 0 and then
      To_String (Value) /= Unavailable_Toolchain_Fingerprint);

   function Compatible
     (Baseline, Current : Ada_Quality.History_Data.History_Item) return Boolean is
     (Baseline.Project_Id = Current.Project_Id and then
      To_String (Baseline.Status) = "completed" and then
      To_String (Current.Status) = "completed" and then
      Length (Baseline.Source_Fingerprint) > 0 and then
      Length (Current.Source_Fingerprint) > 0 and then
      Length (Baseline.Policy_Fingerprint) > 0 and then
      Baseline.Policy_Fingerprint = Current.Policy_Fingerprint and then
      Toolchain_Is_Available (Baseline.Toolchain_Fingerprint) and then
      Baseline.Toolchain_Fingerprint = Current.Toolchain_Fingerprint);

   function Incompatibility_Of
     (Baseline, Current : Ada_Quality.History_Data.History_Item) return Incompatibility is
     (if Baseline.Project_Id /= Current.Project_Id then Other_Project
      elsif To_String (Baseline.Status) /= "completed" or else To_String (Current.Status) /= "completed"
      then Not_Completed
      elsif Length (Baseline.Source_Fingerprint) = 0 or else Length (Current.Source_Fingerprint) = 0
      then Missing_Source_Fingerprint
      elsif Length (Baseline.Policy_Fingerprint) = 0 or else Baseline.Policy_Fingerprint /= Current.Policy_Fingerprint
      then Policy_Changed
      elsif not Toolchain_Is_Available (Baseline.Toolchain_Fingerprint) or else
        Baseline.Toolchain_Fingerprint /= Current.Toolchain_Fingerprint
      then Toolchain_Changed
      else No_Incompatibility);

   function Policy_Comparable
     (Baseline, Current : Ada_Quality.History_Data.History_Item) return Boolean is
     (Baseline.Project_Id = Current.Project_Id and then
      To_String (Baseline.Status) = "completed" and then
      To_String (Current.Status) = "completed" and then
      Length (Baseline.Source_Fingerprint) > 0 and then
      Length (Current.Source_Fingerprint) > 0 and then
      Length (Baseline.Policy_Fingerprint) > 0 and then
      Length (Current.Policy_Fingerprint) > 0 and then
      Baseline.Policy_Fingerprint /= Current.Policy_Fingerprint and then
      Toolchain_Is_Available (Baseline.Toolchain_Fingerprint) and then
      Baseline.Toolchain_Fingerprint = Current.Toolchain_Fingerprint);

   function Baseline_Id
     (Runs : Ada_Quality.History_Data.History_Vectors.Vector;
      Current_Id : Positive) return Natural
   is
      Current_Index : Natural := 0;
   begin
      if Runs.Is_Empty then
         return 0;
      end if;

      for Index in Runs.First_Index .. Runs.Last_Index loop
         if Runs (Index).Id = Current_Id then Current_Index := Index; exit; end if;
      end loop;
      if Current_Index = 0 or else Current_Index = Runs.First_Index then return 0; end if;
      for Index in reverse Runs.First_Index .. Current_Index - 1 loop
         if Compatible (Runs (Index), Runs (Current_Index)) then return Runs (Index).Id; end if;
      end loop;
      return 0;
   end Baseline_Id;

   function Select_Comparison
     (Runs : Ada_Quality.History_Data.History_Vectors.Vector) return Comparison_Selection
   is
      Result : Comparison_Selection;
   begin
      if Runs.Is_Empty then
         return Result;
      end if;
      declare
         Current : constant History_Item := Runs.Last_Element;
      begin
         Result.Current_Id := Current.Id;
         if To_String (Current.Status) /= "completed" then
            Result.Status := Current_Incomplete;
         elsif Runs.Length < 2 then
            Result.Status := No_Baseline;
         else
            Result.Baseline_Id := Baseline_Id (Runs, Current.Id);
            if Result.Baseline_Id > 0 then
               Result.Status := Comparison_Available;
            else
               declare
                  Previous : constant History_Item := Runs (Runs.Last_Index - 1);
               begin
                  if Policy_Comparable (Previous, Current) then
                     Result.Status := Comparison_Available;
                     Result.Baseline_Id := Previous.Id;
                     Result.Policy_Changed := True;
                  elsif To_String (Previous.Status) /= "completed" then
                     Result.Status := No_Completed_Baseline;
                  elsif Previous.Toolchain_Fingerprint /= Current.Toolchain_Fingerprint then
                     Result.Status := Toolchain_Changed;
                  else
                     Result.Status := No_Compatible_Baseline;
                  end if;
               end;
            end if;
         end if;
      end;
      return Result;
   end Select_Comparison;

   procedure Include_Findings
     (Index : in out Finding_Index;
      Items : Ada_Quality.History_Data.Detail_Vectors.Vector)
   is
   begin
      for Item of Items loop
         Index.Keys.Include (Item.Kind);
         declare
            Alias : constant Unbounded_String := Legacy_Finding_Key (Item.Kind);
         begin
            if Index.Alias_Counts.Contains (Alias) then
               Index.Alias_Counts.Replace (Alias, Index.Alias_Counts.Element (Alias) + 1);
            else
               Index.Alias_Counts.Insert (Alias, 1);
            end if;
         end;
      end loop;
   end Include_Findings;

   function Alias_Count (Index : Finding_Index; Key : Unbounded_String) return Natural is
      Alias : constant Unbounded_String := Legacy_Finding_Key (Key);
   begin
      return (if Index.Alias_Counts.Contains (Alias) then Index.Alias_Counts.Element (Alias) else 0);
   end Alias_Count;

   function Contains_Finding
     (Index : Finding_Index; Fingerprint : Unbounded_String) return Boolean is
     (Index.Keys.Contains (Fingerprint) or else
      (Alias_Count (Index, Fingerprint) = 1 and then
       Index.Keys.Contains (Legacy_Finding_Key (Fingerprint))));

   function Build_Finding_Classifier
     (Current, Previous, Older : Ada_Quality.History_Data.Detail_Vectors.Vector)
      return Finding_Classifier
   is
      Result : Finding_Classifier;
   begin
      Include_Findings (Result.Current, Current);
      Include_Findings (Result.Previous, Previous);
      Include_Findings (Result.Older, Older);
      return Result;
   end Build_Finding_Classifier;

   function Classify_Finding
     (Item             : Finding_Classifier;
      Fingerprint      : Unbounded_String;
      Current_Complete : Boolean) return Finding_Lifecycle
   is
      In_Current  : constant Boolean := Contains_Finding (Item.Current, Fingerprint);
      In_Previous : constant Boolean := Contains_Finding (Item.Previous, Fingerprint);
      Alias       : constant Unbounded_String := Legacy_Finding_Key (Fingerprint);
      Ambiguous_Legacy_Match : constant Boolean :=
        Alias /= Fingerprint and then Alias_Count (Item.Current, Fingerprint) > 1 and then
        not Item.Previous.Keys.Contains (Fingerprint) and then Item.Previous.Keys.Contains (Alias);
   begin
      if not Current_Complete and then In_Previous then return Unconfirmed;
      elsif Ambiguous_Legacy_Match then return Unconfirmed;
      elsif In_Current and then In_Previous then return Persistent;
      elsif In_Current and then Contains_Finding (Item.Older, Fingerprint) then return Reintroduced;
      elsif In_Current then return New_Finding;
      elsif In_Previous then return Resolved;
      else return Unconfirmed;
      end if;
   end Classify_Finding;

   function Classify_Finding
     (Fingerprint      : Unbounded_String;
      Current, Previous, Older : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Current_Complete : Boolean) return Finding_Lifecycle
   is
      Classifier : constant Finding_Classifier :=
        Build_Finding_Classifier (Current, Previous, Older);
   begin
      return Classify_Finding (Classifier, Fingerprint, Current_Complete);
   end Classify_Finding;

   function Detail
     (Items : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Key   : Unbounded_String;
      Found : out Boolean) return Ada_Quality.History_Data.Detail_Info
   is
   begin
      for Item of Items loop
         if Item.Kind = Key then Found := True; return Item; end if;
      end loop;
      Found := False;
      return
        (Id => 1, Run_Id => 1, Kind => Null_Unbounded_String,
         State => Null_Unbounded_String, Summary => Null_Unbounded_String);
   end Detail;

   function Number
     (Item  : Ada_Quality.History_Data.Detail_Info;
      Found : out Boolean) return Long_Long_Integer
   is
      Value : Measurement_Value;
   begin
      if not Ada_Quality.Persistence.Decode_Measurement
        (To_String (Item.State), To_String (Item.Summary), Value)
      then
         Found := False;
         return 0;
      end if;
      case Value.Kind is
         when Integer_Value =>
            Found := True;
            return Value.Integer_Data;
         when Decimal_Value =>
            Found := True;
            return Value.Basis_Points;
         when others =>
            Found := False;
            return 0;
      end case;
   end Number;

   function Is_Worse
     (Id : Indicator_Id; Before, After : Long_Long_Integer) return Boolean is
     (case Direction_Of (Id) is
         when Higher_Is_Better => After < Before,
         when Lower_Is_Better  => After > Before,
         when No_Trend         => False);

   function Increased_Severity (Before, After : String) return Boolean is
      Old_Level, New_Level : Severity;
   begin
      return Ada_Quality.Persistence.Decode_Severity (Before, Old_Level) and then
        Ada_Quality.Persistence.Decode_Severity (After, New_Level) and then
        Severity'Pos (New_Level) > Severity'Pos (Old_Level);
   end Increased_Severity;

   procedure Compare_One_Finding
     (New_Finding   : Detail_Info;
      Baseline      : Detail_Key_Maps.Map;
      Older         : Finding_Index;
      Consumed      : in out Finding_Key_Sets.Set;
      Found         : out Boolean;
      Change        : out Regression)
   is
      Legacy_Key  : constant Unbounded_String := Legacy_Finding_Key (New_Finding.Kind);
      Exact_Found : constant Boolean := Baseline.Contains (New_Finding.Kind);
      Legacy_Found : constant Boolean :=
        not Exact_Found and then Legacy_Match_Available
          (Baseline, Consumed, New_Finding.Kind, Legacy_Key);
      Old_Key   : constant Unbounded_String :=
        (if Exact_Found then New_Finding.Kind else Legacy_Key);
      Old_Found : constant Boolean := Exact_Found or else Legacy_Found;
      Id        : Indicator_Id;
   begin
      Found := False;
      Change := (others => <>);
      if not Finding_Indicator (New_Finding.Kind, Id) then
         return;
      end if;
      if Legacy_Found then
         Consumed.Insert (Legacy_Key);
      end if;
      if not Old_Found then
         Change :=
           (Indicator => Id,
            Kind => (if Contains_Finding (Older, New_Finding.Kind)
                     then Reintroduced_Finding else Introduced_Finding),
            Before => To_Unbounded_String ("absent"),
            After => To_Unbounded_String
              (To_String (New_Finding.Kind) & " " & To_String (New_Finding.Summary)));
         Found := True;
      elsif Increased_Severity
        (To_String (Baseline.Element (Old_Key).State), To_String (New_Finding.State))
      then
         Change :=
           (Indicator => Id, Kind => Increased_Severity,
            Before => Baseline.Element (Old_Key).State, After => New_Finding.State);
         Found := True;
      end if;
   end Compare_One_Finding;

   function Semantic_Identity (State : Unbounded_String) return Unbounded_String;

   function Index_Details (Items : Detail_Vectors.Vector) return Detail_Key_Maps.Map is
      Index : Detail_Key_Maps.Map;
   begin
      for Item of Items loop
         if not Index.Contains (Item.Kind) then
            Index.Insert (Item.Kind, Item);
         end if;
      end loop;
      return Index;
   end Index_Details;

   procedure Add_Regression
     (Result : in out Regression_Vectors.Vector;
      Id     : Indicator_Id;
      Kind   : Regression_Kind;
      Before, After : String) is
   begin
      Result.Append
        (Regression'(Indicator => Id, Kind => Kind,
         Before => To_Unbounded_String (Before), After => To_Unbounded_String (After)));
   end Add_Regression;

   procedure Compare_State
     (New_Item         : Detail_Info;
      Baseline_Results : Detail_Vectors.Vector;
      Policy_Changed   : Boolean;
      Result           : in out Regression_Vectors.Vector)
   is
      Old_Found : Boolean;
      Old_Item  : constant Detail_Info := Detail (Baseline_Results, New_Item.Kind, Old_Found);
      Id        : Indicator_Id;
      Parsed    : constant Boolean :=
        Ada_Quality.Indicators.Parse_Canonical (To_String (New_Item.Kind), Id);
      Old_Execution, New_Execution : Execution_Status;
      Old_Compliance, New_Compliance : Compliance_Status;
   begin
      if not Old_Found or else not Parsed or else Old_Item.State = New_Item.State or else
        not Ada_Quality.Persistence.Decode_Result_State
          (To_String (Old_Item.State), Old_Execution, Old_Compliance) or else
        not Ada_Quality.Persistence.Decode_Result_State
          (To_String (New_Item.State), New_Execution, New_Compliance)
      then
         return;
      end if;
      if Policy_Changed then
         Add_Regression
           (Result, Id, Policy_Induced_Change, To_String (Old_Item.State), To_String (New_Item.State));
      elsif New_Compliance = Violation and then Old_Compliance = Pass then
         Add_Regression
           (Result, Id, (if Is_Gate (Id) then Failed_Gate else New_Violation),
            To_String (Old_Item.State), To_String (New_Item.State));
      elsif New_Compliance not in Pass | Violation then
         Add_Regression
           (Result, Id, Lost_Evidence, To_String (Old_Item.State), To_String (New_Item.State));
      end if;
   end Compare_State;

   procedure Compare_Metric
     (New_Item              : Detail_Info;
      Baseline_Results      : Detail_Vectors.Vector;
      Baseline_Measurements : Detail_Vectors.Vector;
      Current_Measurements  : Detail_Vectors.Vector;
      Policy_Changed        : Boolean;
      Result                : in out Regression_Vectors.Vector)
   is
      Old_Found : Boolean;
      Id        : Indicator_Id;
      Parsed    : constant Boolean :=
        Ada_Quality.Indicators.Parse_Canonical (To_String (New_Item.Kind), Id);
      Old_Number, New_Number : Long_Long_Integer;
      Old_Number_Found, New_Number_Found : Boolean;
      Old_Measurement_Found, New_Measurement_Found : Boolean;
   begin
      if Policy_Changed or else not Parsed then return; end if;
      declare
         Old_Item : constant Detail_Info := Detail (Baseline_Results, New_Item.Kind, Old_Found);
         pragma Unreferenced (Old_Item);
      begin
         if not Old_Found then return; end if;
      end;
      declare
         Old_Measurement : constant Detail_Info :=
           Detail (Baseline_Measurements, New_Item.Kind, Old_Measurement_Found);
         New_Measurement : constant Detail_Info :=
           Detail (Current_Measurements, New_Item.Kind, New_Measurement_Found);
         Old_Semantics : constant Unbounded_String := Semantic_Identity (Old_Measurement.State);
         New_Semantics : constant Unbounded_String := Semantic_Identity (New_Measurement.State);
      begin
         if not Old_Measurement_Found or else not New_Measurement_Found or else
           Old_Semantics /= New_Semantics or else Length (Old_Semantics) = 0
         then
            return;
         end if;
         Old_Number := Number (Old_Measurement, Old_Number_Found);
         New_Number := Number (New_Measurement, New_Number_Found);
         if Old_Number_Found and then New_Number_Found and then Is_Worse (Id, Old_Number, New_Number) then
            Add_Regression
              (Result, Id, Worsened_Metric, Long_Long_Integer'Image (Old_Number),
               Long_Long_Integer'Image (New_Number));
         end if;
      end;
   end Compare_Metric;

   function Compare
     (Baseline, Current : Ada_Quality.History_Data.History_Item;
      Baseline_Results, Current_Results : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Measurements, Current_Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Findings, Current_Findings : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Older_Index : Finding_Index)
      return Regression_Vectors.Vector
   is
      Result : Regression_Vectors.Vector;
      Policy_Changed : constant Boolean := Baseline.Policy_Fingerprint /= Current.Policy_Fingerprint;

      Baseline_Finding_Index : constant Detail_Key_Maps.Map := Index_Details (Baseline_Findings);
      Consumed_Legacy_Findings : Finding_Key_Sets.Set;
   begin
      if To_String (Baseline.Status) /= "completed" or else To_String (Current.Status) /= "completed" then
         return Result;
      elsif Baseline.Project_Id /= Current.Project_Id or else
        not Toolchain_Is_Available (Baseline.Toolchain_Fingerprint) or else
        Baseline.Toolchain_Fingerprint /= Current.Toolchain_Fingerprint
      then
         return Result;
      end if;
      for New_Item of Current_Results loop
         Compare_State (New_Item, Baseline_Results, Policy_Changed, Result);
         Compare_Metric
           (New_Item, Baseline_Results, Baseline_Measurements, Current_Measurements,
            Policy_Changed, Result);
      end loop;
      if not Policy_Changed then
         for New_Finding of Current_Findings loop
            declare
               Found  : Boolean;
               Change : Regression;
            begin
               Compare_One_Finding
                 (New_Finding, Baseline_Finding_Index, Older_Index,
                  Consumed_Legacy_Findings, Found, Change);
               if Found then Result.Append (Change); end if;
            end;
         end loop;
      end if;
      return Result;
   end Compare;

   function Compare
     (Baseline, Current : Ada_Quality.History_Data.History_Item;
      Baseline_Results, Current_Results : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Measurements, Current_Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Findings, Current_Findings : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Older_Findings : Ada_Quality.History_Data.Detail_Vectors.Vector :=
        Ada_Quality.History_Data.Detail_Vectors.Empty_Vector)
      return Regression_Vectors.Vector
   is
      Older_Finding_Index : Finding_Index;
   begin
      Include_Findings (Older_Finding_Index, Older_Findings);
      return Compare
        (Baseline, Current, Baseline_Results, Current_Results,
         Baseline_Measurements, Current_Measurements,
         Baseline_Findings, Current_Findings, Older_Finding_Index);
   end Compare;

   function Semantic_Identity (State : Unbounded_String) return Unbounded_String is
     (To_Unbounded_String
        (Ada_Quality.Persistence.Measurement_Semantic_Identity (To_String (State))));

   function Latest_Completed
     (Runs : Ada_Quality.History_Data.History_Vectors.Vector) return Natural
   is
   begin
      if Runs.Is_Empty then return 0; end if;
      for Index in reverse Runs.First_Index .. Runs.Last_Index loop
         if To_String (Runs (Index).Status) = "completed" then
            return Index;
         end if;
      end loop;
      return 0;
   end Latest_Completed;

   function Metric_Trend
     (Runs         : Ada_Quality.History_Data.History_Vectors.Vector;
      Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Indicator    : Indicator_Id) return Trend_Vectors.Vector
   is
      Result : Trend_Vectors.Vector;
      Key    : constant Unbounded_String := To_Unbounded_String (Image (Indicator));
      Reference_Index : constant Natural := Latest_Completed (Runs);
      Measurement_Index : Run_Measurement_Maps.Map;
   begin
      if Reference_Index = 0 then return Result; end if;
      for Item of Measurements loop
         if Item.Kind = Key and then not Measurement_Index.Contains (Item.Run_Id) then
            Measurement_Index.Insert (Item.Run_Id, Item);
         end if;
      end loop;
      declare
         Reference : constant History_Item := Runs (Reference_Index);
         Reference_Semantics : constant Unbounded_String :=
           (if Measurement_Index.Contains (Reference.Id)
            then Semantic_Identity (Measurement_Index.Element (Reference.Id).State)
            else Null_Unbounded_String);
      begin
         if Length (Reference_Semantics) = 0 then return Result; end if;
         for Run of Runs loop
            if Compatible (Run, Reference) and then Measurement_Index.Contains (Run.Id) then
               declare
                  Item : constant Detail_Info := Measurement_Index.Element (Run.Id);
                  Found : Boolean;
                  Value : Long_Long_Integer;
               begin
                  if Semantic_Identity (Item.State) = Reference_Semantics then
                     Value := Number (Item, Found);
                     if Found then
                        Result.Append (Trend_Point'(Run_Id => Run.Id, Value => Value));
                     end if;
                  end if;
               end;
            end if;
         end loop;
      end;
      return Result;
   end Metric_Trend;

   function Normalized (Text : String) return String is
      Result : String := Ada.Characters.Handling.To_Lower (Text);
   begin
      for C of Result loop
         if C = '_' then C := '-'; end if;
      end loop;
      return Result;
   end Normalized;

   function Image (Value : Finding_Lifecycle) return String is
     (Normalized (Finding_Lifecycle'Image (Value)));

   function Image (Value : Regression_Kind) return String is
     (Normalized (Regression_Kind'Image (Value)));

   function Image (Value : Comparison_Status) return String is
     (Normalized (Comparison_Status'Image (Value)));

   function Image (Value : Incompatibility) return String is
     (Normalized (Incompatibility'Image (Value)));
end Ada_Quality.History;
