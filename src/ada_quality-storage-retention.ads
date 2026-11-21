with Ada.Calendar;

--  Internal retention planning isolated from storage transaction orchestration.
private package Ada_Quality.Storage.Retention is
   function Candidates
     (Item : in out Store; Before : Ada.Calendar.Time; Keep : Natural)
      return History_Vectors.Vector;
end Ada_Quality.Storage.Retention;
