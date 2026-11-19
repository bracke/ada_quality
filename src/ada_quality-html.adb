with Ada.Strings.Unbounded;
with Ada_Quality.History;

package body Ada_Quality.HTML is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;

   function Escape (Text : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for C of Text loop
         case C is
            when '&' => Append (Result, "&amp;");
            when '<' => Append (Result, "&lt;");
            when '>' => Append (Result, "&gt;");
            when '"' => Append (Result, "&quot;");
            when ''' => Append (Result, "&#39;");
            when others => Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape;

   function Header (Title : String) return String is
     ("<!doctype html><html lang=""en""><head><meta charset=""utf-8"">" &
      "<meta name=""viewport"" content=""width=device-width,initial-scale=1"">" &
      "<title>" & Escape (Title) & "</title><style>" &
      "body{font:15px system-ui;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#17202a}" &
      "table{border-collapse:collapse;width:100%}th,td{padding:.45rem;border-bottom:1px solid #ddd;text-align:left}" &
      "th{background:#f4f6f7}.pass{color:#18713c}.violation{color:#b42318}.unknown{color:#8a4b08}" &
      "code{font-family:ui-monospace,monospace}</style></head><body>");

   function Render_Assessment (Item : Assessment) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String :=
        To_Unbounded_String (Header ("Ada Quality assessment"));
   begin
      Append (Result, "<h1>Assessment " & Natural'Image (Item.Id) & "</h1>");
      Append (Result, "<p>Project <code>" & Escape (To_String (Item.Project_Path)) & "</code></p>");
      Append (Result, "<table><thead><tr><th>Indicator</th><th>Execution</th>" &
        "<th>Compliance</th><th>Summary</th></tr></thead><tbody>");
      for Value of Item.Results loop
         Append
           (Result, "<tr><td><code>" & Image (Value.Indicator) & "</code></td><td>" &
            Escape (Image (Value.Execution)) & "</td><td class=""" &
            (case Value.Compliance is
                when Pass => "pass",
                when Violation => "violation",
                when others => "unknown") & """>" & Escape (Image (Value.Compliance)) &
            "</td><td>" & Escape (To_String (Value.Summary)) & "</td></tr>");
      end loop;
      Append (Result, "</tbody></table></body></html>" & ASCII.LF);
      return To_String (Result);
   end Render_Assessment;

   function Render_Portfolio
     (Item : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector) return String
   is
      Result : Ada.Strings.Unbounded.Unbounded_String :=
        To_Unbounded_String (Header ("Ada Quality portfolio"));
   begin
      Append (Result, "<h1>Ada Quality portfolio</h1><table><thead><tr><th>Project</th>" &
        "<th>Path</th><th>Latest assessment</th><th>Comparison</th><th>Regressions</th></tr></thead><tbody>");
      for Project of Projects loop
         declare
            Runs : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
              Ada_Quality.Reporting.Runs (Item, Project.Id);
            Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
              Ada_Quality.Reporting.Compare_Project (Item, Project.Id);
            Latest : constant String :=
              (if Runs.Is_Empty then "never"
               else Positive'Image (Runs.Last_Element.Id) & " " &
                 Assessment_Status'Image (Runs.Last_Element.State));
         begin
            Append
              (Result, "<tr><td>" & Positive'Image (Project.Id) & "</td><td><code>" &
               Escape (To_String (Project.Path)) & "</code></td><td>" & Escape (Latest) &
               "</td><td>" & Escape (Ada_Quality.History.Image (Comparison.Selection.Status)) &
               "</td><td>" & Natural'Image (Natural (Comparison.Changes.Length)) & "</td></tr>");
         end;
      end loop;
      Append (Result, "</tbody></table></body></html>" & ASCII.LF);
      return To_String (Result);
   end Render_Portfolio;
end Ada_Quality.HTML;
