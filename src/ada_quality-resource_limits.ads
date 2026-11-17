--  Shared filesystem resource limits for source inspection and isolated staging.
package Ada_Quality.Resource_Limits is
   Maximum_Tree_Depth        : constant Positive := 128;
   Maximum_Project_Files     : constant Positive := 100_000;
   Maximum_File_Bytes        : constant Positive := 64 * 1_024 * 1_024;
   Maximum_Aggregate_Bytes   : constant Positive := 1_024 * 1_024 * 1_024;
   Maximum_Staging_File_Bytes : constant Positive := 256 * 1_024 * 1_024;
   Maximum_Staging_Aggregate_Bytes : constant Long_Long_Integer :=
     4 * 1_024 * 1_024 * 1_024;
end Ada_Quality.Resource_Limits;
