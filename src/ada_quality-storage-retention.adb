with Ada.Containers.Ordered_Maps;
with Ada.Strings.Unbounded;
with Ada_Quality.Persistence;
with Ada_Quality.Storage.Assessments;

package body Ada_Quality.Storage.Retention is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Persistence;
   use type Ada.Calendar.Time;

   function Candidates
     (Item : in out Store; Before : Ada.Calendar.Time; Keep : Natural)
      return History_Vectors.Vector
   is
      package Count_Maps is new Ada.Containers.Ordered_Maps (Positive, Natural);
      Runs        : constant History_Vectors.Vector :=
        Ada_Quality.Storage.Assessments.History (Item);
      Result      : History_Vectors.Vector;
      Per_Project : Count_Maps.Map;
   begin
      for Index in reverse Runs.First_Index .. Runs.Last_Index loop
         declare
            Run     : constant History_Item := Runs (Index);
            Payload : Assessment_Payload_Data;
            Seen    : Natural :=
              (if Per_Project.Contains (Run.Project_Id)
               then Per_Project.Element (Run.Project_Id)
               else 0);
         begin
            if To_String (Run.Status) /= "running" and then
              Decode_Assessment_Payload (To_String (Run.Summary), Payload)
            then
               if Seen < Keep then
                  Seen := Seen + 1;
               elsif Payload.Finished_At.Present and then
                 Payload.Finished_At.Value < Before
               then
                  Result.Append (Run);
               end if;
               Per_Project.Include (Run.Project_Id, Seen);
            end if;
         end;
      end loop;
      Result.Reverse_Elements;
      return Result;
   end Candidates;
end Ada_Quality.Storage.Retention;
