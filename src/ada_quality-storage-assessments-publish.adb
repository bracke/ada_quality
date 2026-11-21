separate (Ada_Quality.Storage.Assessments)
function Publish (Item : in out Store; Value : Assessment) return Positive is
   function Finding_Count return Natural is
      Result : Natural := 0;
   begin
      for Indicator of Value.Results loop
         Result := Result + Natural (Indicator.Findings.Length);
      end loop;
      return Result;
   end Finding_Count;

   Result_Count : constant Natural := Natural (Value.Results.Length);
   Run_Id       : Positive := 1;
   Result_Id    : Natural := 0;
   Measure_Id   : Natural := 0;
   Finding_Id   : Natural := 0;
   Execution_Id : Natural := 0;
   Event_Id     : Positive := 1;
   Stamp      : constant String := (if Item.Legacy_Testing_Evidence then "" else UTC_Now);
   Tx         : Database.Transactions.Transaction;
   Status     : Database.Status.Result;
   Run_Row    : Entity;

   procedure Insert (Table : Positive; Row : Entity; Context : String) is
   begin
      Status := Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Table), Row);
      if not Database.Status.Is_Ok (Status) then
         raise Storage_Error with Context;
      end if;
   end Insert;

   procedure Publish_Run is
   begin
      if Value.Id = 0 then
         Insert
           (Assessments_Table,
            (Id => Run_Id, Parent_Id => Value.Project_Id, Kind => WW ("assessment"),
             State => WW (Assessment_Status_Image (Value.Status)),
             Payload => WW (Assessment_Payload
               (To_String (Value.Source_Fingerprint), To_String (Value.Policy_Fingerprint),
                To_String (Value.Toolchain_Fingerprint), Started_At => Stamp, Finished_At => Stamp,
                Lossless => not Item.Legacy_Testing_Evidence)),
             Active => Value.Status = Assessment_Completed), "insert assessment");
      else
         Status := Entity_Tables.Find
           (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Id, Run_Row);
         if not Database.Status.Is_Ok (Status) or else S (Run_Row.State) /= "running" then
            raise Storage_Error with "assessment publication requires a running record";
         elsif Run_Row.Parent_Id /= Value.Project_Id then
            raise Storage_Error with "assessment publication project does not own the running record";
         end if;
         Run_Row.State := WW (Assessment_Status_Image (Value.Status));
         Run_Row.Payload :=
           WW (Assessment_Payload
             (To_String (Value.Source_Fingerprint), To_String (Value.Policy_Fingerprint),
              To_String (Value.Toolchain_Fingerprint), Started_At => Field (S (Run_Row.Payload), "started_at"),
              Finished_At => Stamp, Lossless => not Item.Legacy_Testing_Evidence));
         Run_Row.Active := Value.Status = Assessment_Completed;
         Status := Entity_Tables.Update
           (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Row);
         if not Database.Status.Is_Ok (Status) then
            raise Storage_Error with "update running assessment";
         end if;
      end if;
   end Publish_Run;

   procedure Publish_Children is
   begin
      for R of Value.Results loop
         Insert
           (Indicator_Results_Table,
            (Id => Positive (Result_Id), Parent_Id => Run_Id, Kind => WW (Image (R.Indicator)),
             State => WW (Image (R.Execution) & "/" & Image (R.Compliance)),
             Payload => WW
               (if Item.Legacy_Testing_Evidence then
                  To_String (R.Summary) & Character'Val (10) & To_String (R.Evidence)
                else Result_Payload (R)),
             Active => R.Compliance = Pass), "insert indicator result");
         Result_Id := Result_Id + 1;
         Insert
           (Measurements_Table,
            (Id => Positive (Measure_Id), Parent_Id => Run_Id, Kind => WW (Image (R.Indicator)),
             State => WW (Measurement_State (R.Indicator, R.Measurement.Kind)),
             Payload => WW (Image (R.Measurement)), Active => R.Execution = Succeeded), "insert measurement");
         Measure_Id := Measure_Id + 1;
         for F of R.Findings loop
            Insert
              (Findings_Table,
               (Id => Positive (Finding_Id), Parent_Id => Run_Id, Kind => WW (To_String (F.Fingerprint)),
                State => WW (Severity'Image (F.Level)),
                Payload => WW
                  (if Item.Legacy_Testing_Evidence then
                     To_String (F.Rule) & Character'Val (10) & To_String (F.Message)
                   else Finding_Payload (F)),
                Active => True),
               "insert finding");
            Finding_Id := Finding_Id + 1;
         end loop;
      end loop;
      for Execution of Value.Executions loop
         Insert
           (Executions_Table,
            (Id => Positive (Execution_Id), Parent_Id => Run_Id, Kind => WW (To_String (Execution.Tool)),
             State => WW (Image (Execution.Status)),
             Payload => WW (Execution_Payload (Execution)),
             Active => Execution.Status = Tool_Completed),
            "insert tool execution");
         Execution_Id := Execution_Id + 1;
      end loop;
      Insert
        (Events_Table,
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("published"),
          State => WW (Assessment_Status_Image (Value.Status)),
          Payload => WW ("atomic publication"), Active => True),
         "insert event");
   end Publish_Children;
begin
   if not Is_Publishable (Value) then
      raise Storage_Error with "assessment is not a complete valid terminal result set";
   end if;
   if Value.Id = 0 then
      declare
         Registered : constant Project_Info :=
           Ada_Quality.Storage.Registry.Project
             (Item, Positive (Value.Project_Id));
         pragma Unreferenced (Registered);
      begin
         null;
      end;
   end if;
   --  Reserve identifiers only after the complete value and its project
   --  ownership have passed validation.
   Run_Id :=
     (if Value.Id = 0 then Next_Id (Item, Assessments_Table) else Positive (Value.Id));
   Result_Id := Reserve_Ids (Item, Indicator_Results_Table, Result_Count);
   Measure_Id := Reserve_Ids (Item, Measurements_Table, Result_Count);
   Finding_Id := Reserve_Ids (Item, Findings_Table, Finding_Count);
   Execution_Id := Reserve_Ids
     (Item, Executions_Table, Natural (Value.Executions.Length));
   Event_Id := Next_Id (Item, Events_Table);
   Database.Transactions.Begin_Write (Item.DB, Tx);
   Publish_Run;
   Publish_Children;
   Trigger_Testing_Fault (Item, Assessment_Publication_Commit);
   Require_OK (Database.Transactions.Commit (Tx), "publish assessment");
   return Run_Id;
exception
   when others =>  --  AQ: audited exception boundary
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Publish;
