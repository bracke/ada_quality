--  Human-readable terminal presentation independent of ANSI color selection.
package Ada_Quality.Presentation is
   function Result_Line
     (Marker, Indicator, Summary : String) return String;
   --  Format one human-readable indicator result without embedding ANSI escapes.
   --  @param Marker Short status marker.
   --  @param Indicator Stable indicator identifier.
   --  @param Summary Human-readable result summary.
   --  @return Localized result line suitable for terminal decoration.
end Ada_Quality.Presentation;
