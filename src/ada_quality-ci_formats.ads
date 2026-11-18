with Ada_Quality.Types;

--  Deterministic CI-native renderers for one completed assessment.
package Ada_Quality.CI_Formats is
   function Render_SARIF
     (Item : Ada_Quality.Types.Assessment;
      Pretty : Boolean := False) return String;
   --  Render assessment findings as a SARIF 2.1.0 log.

   function Render_JUnit (Item : Ada_Quality.Types.Assessment) return String;
   --  Render the complete indicator result set as one JUnit XML suite.
end Ada_Quality.CI_Formats;
