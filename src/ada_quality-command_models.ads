with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Checks;
with Ada_Quality.History;
with Ada_Quality.Reporting;
with Ada_Quality.Types;

--  Presentation-neutral command result models shared by CLI front ends.
package Ada_Quality.Command_Models is
   type Page_Info is record
      Present     : Boolean := False;
      Total       : Natural := 0;
      Offset      : Natural := 0;
      Limit       : Natural := 0;
      Next_Cursor : Ada.Strings.Unbounded.Unbounded_String;
      Snapshot    : Natural := 0;
   end record;

   type Batch_Outcome_Status is
     (Batch_Completed, Batch_Reused, Batch_Interrupted);

   type Batch_Outcome is record
      Project_Id    : Natural := 0;
      Assessment_Id : Natural := 0;
      Status        : Batch_Outcome_Status := Batch_Interrupted;
      Diagnostic    : Ada.Strings.Unbounded.Unbounded_String;
      Value         : Ada_Quality.Types.Assessment;
   end record;
   package Batch_Outcome_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Batch_Outcome);

   type Check_Plan_Item is record
      Project_Id              : Positive;
      Path                    : Ada.Strings.Unbounded.Unbounded_String;
      Source_Fingerprint      : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Fingerprint      : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Fingerprint   : Ada.Strings.Unbounded.Unbounded_String;
      Reusable_Assessment     : Natural := 0;
      Will_Reuse              : Boolean := False;
   end record;
   package Check_Plan_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Check_Plan_Item);

   type Metric_Series is record
      Indicator : Ada_Quality.Types.Indicator_Id := Ada_Quality.Types.STR_01;
      Unit_Name : Ada.Strings.Unbounded.Unbounded_String;
      Points    : Ada_Quality.History.Trend_Vectors.Vector;
   end record;
   package Metric_Series_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Metric_Series);

   type Discovery_Status is
     (Already_Registered, Discovered, Added, Missing, Removed);
   type Discovery_Item is record
      Path       : Ada.Strings.Unbounded.Unbounded_String;
      Project_Id : Natural := 0;
      Status     : Discovery_Status := Discovered;
   end record;
   package Discovery_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Discovery_Item);

   type Diagnostic_Item is record
      Name   : Ada.Strings.Unbounded.Unbounded_String;
      Passed : Boolean := False;
      Detail : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   package Diagnostic_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Diagnostic_Item);

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   type Diagnostic_Report is record
      Project_Id : Natural := 0;
      Path       : Ada.Strings.Unbounded.Unbounded_String;
      Checks     : Diagnostic_Vectors.Vector;
   end record;
   package Diagnostic_Report_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Diagnostic_Report);

   type Waiver_Report is record
      Project_Id : Positive;
      Path       : Ada.Strings.Unbounded.Unbounded_String;
      Waivers    : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
   end record;
   package Waiver_Report_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Waiver_Report);

   type Policy_Impact_Item is record
      Project_Id         : Positive;
      Path               : Ada.Strings.Unbounded.Unbounded_String;
      Before_Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
      After_Fingerprint  : Ada.Strings.Unbounded.Unbounded_String;
      Keys               : String_Vectors.Vector;
      Indicators         : String_Vectors.Vector;
   end record;
   package Policy_Impact_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Policy_Impact_Item);

   package Comparison_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada_Quality.Reporting.Project_Comparison,
      "=" => Ada_Quality.Reporting."=");
end Ada_Quality.Command_Models;
