with Messages.Arguments;
with Messages.Result;
with Messages.Runtime;

package body Ada_Quality.Presentation is
   use type Messages.Result.Render_Status;
   use type Messages.Runtime.Load_Status;

   Catalog : constant String :=
     "default_locale=en" & ASCII.LF &
     "en.assessment_result = {marker} {indicator} {summary}" & ASCII.LF;

   function Result_Line
     (Marker, Indicator, Summary : String) return String
   is
      Runtime : Messages.Runtime.Instance;
      Loaded  : Messages.Runtime.Load_Result;
      Args    : Messages.Arguments.Arguments;
   begin
      Messages.Runtime.Load_Text (Runtime, "ada-quality", Catalog, Loaded);
      if Loaded.Status /= Messages.Runtime.Loaded then
         Messages.Runtime.Finalize (Runtime);
         return Marker & " " & Indicator & " " & Summary;
      end if;
      Messages.Arguments.Set (Args, "marker", Marker);
      Messages.Arguments.Set (Args, "indicator", Indicator);
      Messages.Arguments.Set (Args, "summary", Summary);
      declare
         Rendered : constant Messages.Result.Render_Result :=
           Messages.Runtime.Render (Runtime, "en", "assessment_result", Args);
      begin
         Messages.Runtime.Finalize (Runtime);
         if Rendered.Status = Messages.Result.Success then
            return Messages.Result.Output_Text (Rendered.Text);
         end if;
      end;
      return Marker & " " & Indicator & " " & Summary;
   exception
      when others =>  --  AQ: audited exception boundary
         Messages.Runtime.Finalize (Runtime);
         return Marker & " " & Indicator & " " & Summary;
   end Result_Line;
end Ada_Quality.Presentation;
