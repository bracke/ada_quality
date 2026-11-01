with AUnit.Test_Suites;

--  Complete Ada Quality test suite composed of the component and reporting suites.
package Ada_Quality_All_Tests is
   --  Complete Ada Quality test suite composed of the component and reporting suites.

   function Suite return AUnit.Test_Suites.Access_Test_Suite;
   --  Return every registered test suite.
   --  @return Composite suite.
end Ada_Quality_All_Tests;
