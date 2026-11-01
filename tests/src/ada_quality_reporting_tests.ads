with AUnit.Test_Suites;

--  Acceptance tests for the read-only reporting API.
package Ada_Quality_Reporting_Tests is
   --  Acceptance tests for the read-only reporting API.

   function Suite return AUnit.Test_Suites.Access_Test_Suite;
   --  Return the reporting test suite.
   --  @return Suite containing every reporting test case.
end Ada_Quality_Reporting_Tests;
