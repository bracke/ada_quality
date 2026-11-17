with Ada.Containers.Ordered_Sets;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.History_Data;
with Ada_Quality.Types;

--  Baseline selection, finding lifecycles, regressions, and metric trends.
package Ada_Quality.History is
   --  Baseline selection, lifecycle classification, regression detection, and trends.
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized persisted history text.

   type Finding_Index is private;
   --  Opaque index of stable finding identities used by bulk history operations.

   type Finding_Lifecycle is (New_Finding, Persistent, Resolved, Reintroduced, Unconfirmed);
   --  Lifecycle classification for a stable finding identity.
   --  @enum New_Finding First appearance in compatible history.
   --  @enum Persistent Present in both adjacent completed assessments.
   --  @enum Resolved Absent from a later complete assessment.
   --  @enum Reintroduced Present again after at least one absence.
   --  @enum Unconfirmed Insufficient complete evidence to classify.

   type Regression_Kind is
     (New_Violation, Worsened_Metric, Increased_Severity, Failed_Gate, Lost_Evidence,
      Introduced_Finding, Reintroduced_Finding, Policy_Induced_Change);
   --  Quality regression classification.
   --  @enum New_Violation A formerly passing nongate requirement now violates policy.
   --  @enum Worsened_Metric A comparable numeric metric moved in the adverse direction.
   --  @enum Increased_Severity A stable finding has a higher severity.
   --  @enum Failed_Gate A formerly passing release gate now violates policy.
   --  @enum Lost_Evidence A formerly evidenced requirement is now blocked or unknown.
   --  @enum Introduced_Finding A stable finding identity is absent from all comparable earlier evidence.
   --  @enum Reintroduced_Finding A finding absent from the baseline returns from older compatible evidence.
   --  @enum Policy_Induced_Change A state changed under a different policy fingerprint.

   type Regression is record
      Indicator : Ada_Quality.Types.Indicator_Id := Ada_Quality.Types.STR_01;
      Kind      : Regression_Kind := New_Violation;
      Before    : Unbounded_String;
      After     : Unbounded_String;
   end record;
   --  One classified change between compatible assessments.
   --  @field Indicator Indicator whose evidence changed.
   --  @field Kind Regression classification.
   --  @field Before Baseline state or value.
   --  @field After Current state or value.

   package Regression_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Regression);
   --  Ordered collection of classified regressions.

   type Trend_Point is record
      Run_Id : Positive;
      Value  : Long_Long_Integer;
   end record;
   --  One numeric measurement in a compatible historical series.
   --  @field Run_Id Assessment identity.
   --  @field Value Persisted numeric measurement.

   package Trend_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Trend_Point);
   --  Ordered collection of trend points.

   type Comparison_Status is
     (Comparison_Available, No_Assessments, No_Baseline, Current_Incomplete,
      No_Completed_Baseline, Toolchain_Changed, No_Compatible_Baseline);
   --  Availability of a historical comparison.

   type Comparison_Selection is record
      Status         : Comparison_Status := No_Assessments;
      Current_Id     : Natural := 0;
      Baseline_Id    : Natural := 0;
      Policy_Changed : Boolean := False;
   end record;
   --  One centralized baseline-selection decision shared by every renderer.

   function Compatible
     (Baseline, Current : Ada_Quality.History_Data.History_Item) return Boolean;
   --  Test whether two completed assessments may be compared directly.
   --  @param Baseline Earlier assessment.
   --  @param Current Later assessment.
   --  @return True when project, policy, and toolchain identities are compatible.

   type Incompatibility is
     (No_Incompatibility, Other_Project, Not_Completed, Missing_Source_Fingerprint, Policy_Changed,
      Toolchain_Changed);
   --  The first reason Compatible rejects a baseline, in the order Compatible tests its conditions.
   --  @enum No_Incompatibility The assessments are compatible.
   --  @enum Other_Project The assessments belong to different projects.
   --  @enum Not_Completed One of the assessments did not complete.
   --  @enum Missing_Source_Fingerprint A source fingerprint is absent.
   --  @enum Policy_Changed The baseline policy fingerprint is absent or differs.
   --  @enum Toolchain_Changed The baseline toolchain fingerprint is unavailable or differs.

   function Incompatibility_Of
     (Baseline, Current : Ada_Quality.History_Data.History_Item) return Incompatibility;
   --  Explain Compatible: the result is No_Incompatibility exactly when Compatible holds.
   --  @param Baseline Earlier assessment.
   --  @param Current Later assessment.
   --  @return First failing condition, or No_Incompatibility.

   function Policy_Comparable
     (Baseline, Current : Ada_Quality.History_Data.History_Item) return Boolean;
   --  Test whether two completed assessments may be compared across a policy change.
   --  @param Baseline Earlier assessment under a different policy.
   --  @param Current Later assessment.
   --  @return True when both runs have complete source and toolchain identity evidence.

   function Baseline_Id
     (Runs : Ada_Quality.History_Data.History_Vectors.Vector;
      Current_Id : Positive) return Natural;
   --  Select the newest compatible assessment preceding Current_Id.
   --  @param Runs Ordered project history.
   --  @param Current_Id Assessment for which a baseline is required.
   --  @return Compatible assessment identity, or zero when none exists.

   function Select_Comparison
     (Runs : Ada_Quality.History_Data.History_Vectors.Vector) return Comparison_Selection;
   --  Select a baseline and preserve the reason when comparison is unavailable.
   --  @param Runs Ordered history for one project.
   --  @return Typed comparison decision for the latest assessment.

   type Finding_Classifier is private;
   --  Indexed current, previous, and older finding evidence.

   function Build_Finding_Classifier
     (Current, Previous, Older : Ada_Quality.History_Data.Detail_Vectors.Vector)
      return Finding_Classifier;
   --  Build one reusable indexed lifecycle classifier.

   function Classify_Finding
     (Item             : Finding_Classifier;
      Fingerprint      : Unbounded_String;
      Current_Complete : Boolean) return Finding_Lifecycle;
   --  Classify one finding using a reusable indexed evidence set.

   procedure Include_Findings
     (Index : in out Finding_Index;
      Items : Ada_Quality.History_Data.Detail_Vectors.Vector);
   --  Add stable identities from Items to a reusable opaque index.

   function Contains_Finding
     (Index : Finding_Index; Fingerprint : Unbounded_String) return Boolean;
   --  Test whether an indexed finding identity is present.

   function Classify_Finding
     (Fingerprint      : Unbounded_String;
      Current, Previous, Older : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Current_Complete : Boolean) return Finding_Lifecycle;
   --  Classify one stable finding across current, previous, and older evidence.
   --  @param Fingerprint Stable finding identity.
   --  @param Current Findings in the current assessment.
   --  @param Previous Findings in the immediately preceding assessment.
   --  @param Older Findings in earlier compatible assessments.
   --  @param Current_Complete Whether absence in Current is authoritative.
   --  @return Finding lifecycle classification.

   function Compare
     (Baseline, Current : Ada_Quality.History_Data.History_Item;
      Baseline_Results, Current_Results : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Measurements, Current_Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Findings, Current_Findings : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Older_Findings : Ada_Quality.History_Data.Detail_Vectors.Vector :=
        Ada_Quality.History_Data.Detail_Vectors.Empty_Vector)
      return Regression_Vectors.Vector;
   --  Compare compatible result, measurement, and finding detail rows.
   --  @param Baseline Earlier assessment metadata.
   --  @param Current Later assessment metadata.
   --  @param Baseline_Results Earlier indicator result rows.
   --  @param Current_Results Later indicator result rows.
   --  @param Baseline_Measurements Earlier typed measurements.
   --  @param Current_Measurements Later typed measurements.
   --  @param Baseline_Findings Earlier finding rows.
   --  @param Current_Findings Later finding rows.
   --  @param Older_Findings Finding rows from compatible assessments older than Baseline.
   --  @return Deterministically ordered regression collection.

   function Compare
     (Baseline, Current : Ada_Quality.History_Data.History_Item;
      Baseline_Results, Current_Results : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Measurements, Current_Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Baseline_Findings, Current_Findings : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Older_Index : Finding_Index)
      return Regression_Vectors.Vector;
   --  Compare evidence using already indexed older finding identities.

   function Metric_Trend
     (Runs         : Ada_Quality.History_Data.History_Vectors.Vector;
      Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Indicator    : Ada_Quality.Types.Indicator_Id) return Trend_Vectors.Vector;
   --  Build a numeric series from compatible completed assessment measurements.
   --  @param Runs Ordered assessment history.
   --  @param Measurements Persisted typed measurement rows.
   --  @param Indicator Numeric indicator to select.
   --  @return Ordered trend points with valid numeric evidence.

   function Image (Value : Finding_Lifecycle) return String;
   --  Return the stable external spelling of a finding lifecycle.
   --  @param Value Lifecycle value.
   --  @return Lowercase hyphenated image.

   function Image (Value : Regression_Kind) return String;
   --  Return the stable external spelling of a regression classification.
   --  @param Value Regression value.
   --  @return Lowercase hyphenated image.

   function Image (Value : Comparison_Status) return String;
   --  Return the stable external spelling of a comparison-selection state.

   function Image (Value : Incompatibility) return String;
   --  Return the stable external spelling of an incompatibility reason.
private
   package Finding_Key_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => Unbounded_String,
      "<" => Ada.Strings.Unbounded."<",
      "=" => Ada.Strings.Unbounded."=");

   package Finding_Count_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Unbounded_String,
      Element_Type => Natural,
      "<" => Ada.Strings.Unbounded."<");

   type Finding_Index is record
      Keys         : Finding_Key_Sets.Set;
      Alias_Counts : Finding_Count_Maps.Map;
   end record;

   type Finding_Classifier is record
      Current  : Finding_Index;
      Previous : Finding_Index;
      Older    : Finding_Index;
   end record;
end Ada_Quality.History;
