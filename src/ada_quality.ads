with Ada_Quality_Config;

--  Root package and semantic version for the Ada Quality application.
package Ada_Quality is
   Version : constant String := Ada_Quality_Config.Crate_Version;
   --  Semantic version of the application and persisted report producer.
end Ada_Quality;
