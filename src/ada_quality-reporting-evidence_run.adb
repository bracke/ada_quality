separate (Ada_Quality.Reporting)
function Evidence_Run
  (Item : Session; Run_Id : Positive; Allow_Terminal : Boolean) return Run_Record
is
begin
   Require_Open (Item);
   if not Item.Run_Index.Contains (Run_Id) then
      raise Reporting_Error with "assessment not found:" & Positive'Image (Run_Id);
   end if;
   declare
      Run : constant Run_Record := Item.All_Runs (Item.Run_Index.Element (Run_Id));
   begin
      if Run.State /= Assessment_Completed and then
        (not Allow_Terminal or else Run.State = Assessment_Running)
      then
         raise Reporting_Error with "assessment has no terminal evidence:" & Positive'Image (Run_Id);
      end if;
      return Run;
   end;
end Evidence_Run;
