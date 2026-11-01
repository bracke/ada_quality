package body Ada_Quality.Tools is
   Programs : constant array (Tool_Id) of access constant String :=
     [Alire => new String'("alr"), GNATls => new String'("gnatls"),
      AUnit => new String'("alr"), Gcov => new String'("gcov"), GNATdoc => new String'("gnatdoc"),
      GNATprove => new String'("gnatprove"), Git => new String'("git"),
      Release_Checker => new String'("check_all")];

   function Registry return Tool_Descriptor_Array is
      Result : Tool_Descriptor_Array;
   begin
      for Id in Tool_Id loop
         Result (Id) := (Id => Id, Program => Programs (Id), Required => Id /= GNATprove);
      end loop;
      return Result;
   end Registry;

   function Program (Id : Tool_Id) return String is (Programs (Id).all);
end Ada_Quality.Tools;
