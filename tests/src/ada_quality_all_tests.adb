with Ada_Quality_Reporting_Tests;
with Ada_Quality_Test_Suite;

package body Ada_Quality_All_Tests is
   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Ada_Quality_Test_Suite.Suite);
      Result.Add_Test (Ada_Quality_Reporting_Tests.Suite);
      return Result;
   end Suite;
end Ada_Quality_All_Tests;
