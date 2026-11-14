with Ada.Containers;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada_Quality.Indicators;

package body Ada_Quality.History is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Storage;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;

   function Contains (Text, Pattern : String) return Boolean is
     (Ada.Strings.Fixed.Index (Text, Pattern) > 0);

   function Compatible
     (Baseline, Current : Ada_Quality.Storage.History_Item) return Boolean is
     (Baseline.Project_Id = Current.Project_Id and then
      To_String (Baseline.Status) = "completed" and then
      To_String (Current.Status) = "completed" and then
      Length (Baseline.Source_Fingerprint) > 0 and then
      Length (Current.Source_Fingerprint) > 0 and then
      Length (Baseline.Policy_Fingerprint) > 0 and then
      Baseline.Policy_Fingerprint = Current.Policy_Fingerprint and then
      Length (Baseline.Toolchain_Fingerprint) > 0 and then
      Baseline.Toolchain_Fingerprint = Current.Toolchain_Fingerprint);

   function Policy_Comparable
     (Baseline, Current : Ada_Quality.Storage.History_Item) return Boolean is
     (Baseline.Project_Id = Current.Project_Id and then
      To_String (Baseline.Status) = "completed" and then
      To_String (Current.Status) = "completed" and then
      Length (Baseline.Source_Fingerprint) > 0 and then
      Length (Current.Source_Fingerprint) > 0 and then
      Length (Baseline.Policy_Fingerprint) > 0 and then
      Length (Current.Policy_Fingerprint) > 0 and then
      Baseline.Policy_Fingerprint /= Current.Policy_Fingerprint and then
      Length (Baseline.Toolchain_Fingerprint) > 0 and then
      Baseline.Toolchain_Fingerprint = Current.Toolchain_Fingerprint);

   function Baseline_Id
     (Runs : Ada_Quality.Storage.History_Vectors.Vector;
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
     (Runs : Ada_Quality.Storage.History_Vectors.Vector) return Comparison_Selection
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

   function Has_Finding
     (Items : Ada_Quality.Storage.Detail_Vectors.Vector;
      Key   : Unbounded_String) return Boolean
   is
   begin
      for Item of Items loop
         if Item.Kind = Key then return True; end if;
      end loop;
      return False;
   end Has_Finding;

   function Classify_Finding
     (Fingerprint      : Unbounded_String;
      Current, Previous, Older : Ada_Quality.Storage.Detail_Vectors.Vector;
      Current_Complete : Boolean) return Finding_Lifecycle
   is
      In_Current  : constant Boolean := Has_Finding (Current, Fingerprint);
      In_Previous : constant Boolean := Has_Finding (Previous, Fingerprint);
   begin
      if not Current_Complete and then In_Previous then return Unconfirmed;
      elsif In_Current and then In_Previous then return Persistent;
      elsif In_Current and then Has_Finding (Older, Fingerprint) then return Reintroduced;
      elsif In_Current then return New_Finding;
      elsif In_Previous then return Resolved;
      else return Unconfirmed;
      end if;
   end Classify_Finding;

   function Detail
     (Items : Ada_Quality.Storage.Detail_Vectors.Vector;
      Key   : Unbounded_String;
      Found : out Boolean) return Ada_Quality.Storage.Detail_Info
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

   function Finding_Detail
     (Items : Ada_Quality.Storage.Detail_Vectors.Vector;
      Key   : Unbounded_String;
      Found : out Boolean) return Ada_Quality.Storage.Detail_Info
   is
   begin
      for Item of Items loop
         if Item.Kind = Key then
            Found := True;
            return Item;
         end if;
      end loop;
      Found := False;
      return
        (Id => 1, Run_Id => 1, Kind => Null_Unbounded_String,
         State => Null_Unbounded_String, Summary => Null_Unbounded_String);
   end Finding_Detail;

   function Number
     (Items : Ada_Quality.Storage.Detail_Vectors.Vector;
      Key   : Unbounded_String;
      Found : out Boolean) return Long_Long_Integer
   is
      Present : Boolean;
      Item    : constant Ada_Quality.Storage.Detail_Info := Detail (Items, Key, Present);
   begin
      if not Present or else not
        (Contains (To_String (Item.State), "INTEGER_VALUE") or else
         Contains (To_String (Item.State), "DECIMAL_VALUE"))
      then
         Found := False;
         return 0;
      end if;
      Found := True;
      return Long_Long_Integer'Value (To_String (Item.Summary));
   exception
      when Constraint_Error => Found := False; return 0;
   end Number;

   function Gate (Id : Indicator_Id) return Boolean is
     (Id in BLD_01 .. BLD_04 or else Id in TST_01 .. TST_04 or else
      Id in REL_01 .. REL_04 or else Id = PRF_01);

   type Metric_Direction is (Higher_Is_Better, Lower_Is_Better, No_Trend);

   function Direction (Id : Indicator_Id) return Metric_Direction is
     (case Id is
         when TST_02 | TST_03 => Higher_Is_Better,
         when SRC_01 | SRC_02 | SRC_03 | SRC_04 | SRC_05 | SRC_06 |
              DOC_01 | SEC_01 | SEC_02 | SEC_03 => Lower_Is_Better,
         when others => No_Trend);

   function Is_Worse
     (Id : Indicator_Id; Before, After : Long_Long_Integer) return Boolean is
     (case Direction (Id) is
         when Higher_Is_Better => After < Before,
         when Lower_Is_Better  => After > Before,
         when No_Trend         => False);

   function Severity_Rank (Text : String) return Natural is
      Upper : constant String := Ada.Characters.Handling.To_Upper (Text);
   begin
      if Contains (Upper, "CRITICAL") then return 4;
      elsif Contains (Upper, "HIGH") then return 3;
      elsif Contains (Upper, "MEDIUM") then return 2;
      elsif Contains (Upper, "LOW") then return 1;
      else return 0;
      end if;
   end Severity_Rank;

   function Compare
     (Baseline, Current : Ada_Quality.Storage.History_Item;
      Baseline_Results, Current_Results : Ada_Quality.Storage.Detail_Vectors.Vector;
      Baseline_Measurements, Current_Measurements : Ada_Quality.Storage.Detail_Vectors.Vector;
      Baseline_Findings, Current_Findings : Ada_Quality.Storage.Detail_Vectors.Vector;
      Older_Findings : Ada_Quality.Storage.Detail_Vectors.Vector :=
        Ada_Quality.Storage.Detail_Vectors.Empty_Vector)
      return Regression_Vectors.Vector
   is
      Result : Regression_Vectors.Vector;
      Policy_Changed : constant Boolean := Baseline.Policy_Fingerprint /= Current.Policy_Fingerprint;

      procedure Add
        (Id : Indicator_Id; Kind : Regression_Kind; Before, After : String) is
      begin
         Result.Append
           (Regression'(Indicator => Id, Kind => Kind,
            Before => To_Unbounded_String (Before), After => To_Unbounded_String (After)));
      end Add;

      procedure Compare_State (New_Item : Ada_Quality.Storage.Detail_Info) is
         Old_Found : Boolean;
         Old_Item  : constant Ada_Quality.Storage.Detail_Info :=
           Detail (Baseline_Results, New_Item.Kind, Old_Found);
         Id        : Indicator_Id;
         Parsed    : constant Boolean := Ada_Quality.Indicators.Parse (To_String (New_Item.Kind), Id);
      begin
         if not Old_Found or else not Parsed or else Old_Item.State = New_Item.State then return; end if;
         if Policy_Changed then
            Add (Id, Policy_Induced_Change, To_String (Old_Item.State), To_String (New_Item.State));
         elsif Contains (To_String (New_Item.State), "/violation") and then
           Contains (To_String (Old_Item.State), "/pass")
         then
            Add (Id, (if Gate (Id) then Failed_Gate else New_Violation),
              To_String (Old_Item.State), To_String (New_Item.State));
         elsif not Contains (To_String (New_Item.State), "/pass") and then
           not Contains (To_String (New_Item.State), "/violation")
         then
            Add (Id, Lost_Evidence, To_String (Old_Item.State), To_String (New_Item.State));
         end if;
      end Compare_State;

      procedure Compare_Metric (New_Item : Ada_Quality.Storage.Detail_Info) is
         Old_Found : Boolean;
         Id        : Indicator_Id;
         Parsed    : constant Boolean := Ada_Quality.Indicators.Parse (To_String (New_Item.Kind), Id);
         Old_Number, New_Number : Long_Long_Integer;
         Old_Number_Found, New_Number_Found : Boolean;
      begin
         if Policy_Changed or else not Parsed then return; end if;
         declare
            Old_Item : constant Ada_Quality.Storage.Detail_Info :=
              Detail (Baseline_Results, New_Item.Kind, Old_Found);
            pragma Unreferenced (Old_Item);
         begin
            if not Old_Found then return; end if;
         end;
         Old_Number := Number (Baseline_Measurements, New_Item.Kind, Old_Number_Found);
         New_Number := Number (Current_Measurements, New_Item.Kind, New_Number_Found);
         if Old_Number_Found and then New_Number_Found and then
           Is_Worse (Id, Old_Number, New_Number)
         then
            Add (Id, Worsened_Metric, Long_Long_Integer'Image (Old_Number),
              Long_Long_Integer'Image (New_Number));
         end if;
      end Compare_Metric;

      procedure Compare_Finding (New_Finding : Ada_Quality.Storage.Detail_Info) is
         Old_Found   : Boolean;
         Old_Finding : constant Ada_Quality.Storage.Detail_Info :=
           Finding_Detail (Baseline_Findings, New_Finding.Kind, Old_Found);
         Colon       : constant Natural := Ada.Strings.Fixed.Index (To_String (New_Finding.Kind), ":");
         Id          : Indicator_Id;
      begin
         if Colon <= 1 then
            return;
         elsif not Ada_Quality.Indicators.Parse (To_String (New_Finding.Kind) (1 .. Colon - 1), Id) then
            return;
         elsif not Old_Found then
            Add
              (Id,
               (if Has_Finding (Older_Findings, New_Finding.Kind)
                then Reintroduced_Finding else Introduced_Finding),
               "absent", To_String (New_Finding.Kind) & " " & To_String (New_Finding.Summary));
         elsif Severity_Rank (To_String (New_Finding.State)) > Severity_Rank (To_String (Old_Finding.State)) then
            Add (Id, Increased_Severity, To_String (Old_Finding.State), To_String (New_Finding.State));
         end if;
      end Compare_Finding;
   begin
      if To_String (Baseline.Status) /= "completed" or else To_String (Current.Status) /= "completed" then
         return Result;
      elsif Baseline.Project_Id /= Current.Project_Id or else
        Length (Baseline.Toolchain_Fingerprint) = 0 or else
        Baseline.Toolchain_Fingerprint /= Current.Toolchain_Fingerprint
      then
         return Result;
      end if;
      for New_Item of Current_Results loop
         Compare_State (New_Item);
         Compare_Metric (New_Item);
      end loop;
      if not Policy_Changed then
         for New_Finding of Current_Findings loop
            Compare_Finding (New_Finding);
         end loop;
      end if;
      return Result;
   end Compare;

   function Semantic_Identity (State : Unbounded_String) return Unbounded_String is
      Text : constant String := To_String (State);
      Indicator_Tag : constant String := ";indicator_version=";
      Method_Tag    : constant String := ";method_version=";
      Indicator_At  : constant Natural := Ada.Strings.Fixed.Index (Text, Indicator_Tag);
      Method_At     : constant Natural := Ada.Strings.Fixed.Index (Text, Method_Tag);
   begin
      if Ada.Strings.Fixed.Index (Text, ";") = 0 then
         return To_Unbounded_String (Text & Indicator_Tag & "1" & Method_Tag & "1");
      elsif Indicator_At = 0 or else Method_At <= Indicator_At + Indicator_Tag'Length then
         return Null_Unbounded_String;
      end if;
      declare
         Indicator_Text : constant String := Text (Indicator_At + Indicator_Tag'Length .. Method_At - 1);
         Method_Text : constant String := Text (Method_At + Method_Tag'Length .. Text'Last);
         Indicator_Version : constant Positive := Positive'Value (Indicator_Text);
         Method_Version : constant Positive := Positive'Value (Method_Text);
         pragma Unreferenced (Indicator_Version, Method_Version);
      begin
         return State;
      end;
   exception
      when Constraint_Error => return Null_Unbounded_String;
   end Semantic_Identity;

   function Latest_Completed
     (Runs : Ada_Quality.Storage.History_Vectors.Vector) return Natural
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

   function Semantics_For
     (Measurements : Ada_Quality.Storage.Detail_Vectors.Vector;
      Run_Id       : Positive;
      Key          : Unbounded_String) return Unbounded_String
   is
   begin
      for Item of Measurements loop
         if Item.Run_Id = Run_Id and then Item.Kind = Key then
            return Semantic_Identity (Item.State);
         end if;
      end loop;
      return Null_Unbounded_String;
   end Semantics_For;

   procedure Append_Trend_Point
     (Result       : in out Trend_Vectors.Vector;
      Measurements : Ada_Quality.Storage.Detail_Vectors.Vector;
      Run           : History_Item;
      Key, Reference_Semantics : Unbounded_String)
   is
   begin
      for Item of Measurements loop
         if Item.Run_Id = Run.Id and then Item.Kind = Key and then
           Semantic_Identity (Item.State) = Reference_Semantics
         then
            declare
               One : Detail_Vectors.Vector;
               Found : Boolean;
               Value : Long_Long_Integer;
            begin
               One.Append (Item);
               Value := Number (One, Key, Found);
               if Found then Result.Append (Trend_Point'(Run_Id => Run.Id, Value => Value)); end if;
            end;
            return;
         end if;
      end loop;
   end Append_Trend_Point;

   function Metric_Trend
     (Runs         : Ada_Quality.Storage.History_Vectors.Vector;
      Measurements : Ada_Quality.Storage.Detail_Vectors.Vector;
      Indicator    : Indicator_Id) return Trend_Vectors.Vector
   is
      Result : Trend_Vectors.Vector;
      Key    : constant Unbounded_String := To_Unbounded_String (Image (Indicator));
      Reference_Index : constant Natural := Latest_Completed (Runs);
   begin
      if Reference_Index = 0 then return Result; end if;
      declare
         Reference : constant History_Item := Runs (Reference_Index);
         Reference_Semantics : constant Unbounded_String :=
           Semantics_For (Measurements, Reference.Id, Key);
      begin
         if Length (Reference_Semantics) = 0 then return Result; end if;
         for Run of Runs loop
            if Compatible (Run, Reference) then
               Append_Trend_Point (Result, Measurements, Run, Key, Reference_Semantics);
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
end Ada_Quality.History;
