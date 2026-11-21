--  Shared filesystem resource limits for source inspection and isolated staging.
package Ada_Quality.Resource_Limits is
   Maximum_Tree_Depth        : constant Positive := 128;
   Maximum_Project_Files     : constant Positive := 100_000;
   Maximum_File_Bytes        : constant Positive := 64 * 1_024 * 1_024;
   Maximum_Aggregate_Bytes   : constant Positive := 1_024 * 1_024 * 1_024;
   Maximum_Staging_File_Bytes : constant Positive := 256 * 1_024 * 1_024;
   Maximum_Staging_Aggregate_Bytes : constant Long_Long_Integer :=
     4 * 1_024 * 1_024 * 1_024;
   Maximum_Security_Metadata_Bytes : constant Positive := 64 * 1_024;
   --  Keys and signature sidecars are small structured records, not artifacts.
   Maximum_Path_Input_Bytes : constant Positive := 4_096;
   Maximum_List_Input_Bytes : constant Positive := 64 * 1_024 * 1_024;
   --  Command list inputs are bounded both per path and in aggregate.
   Maximum_Database_Rows : constant Positive := 2_500_000;
   Maximum_Database_Text_Bytes : constant Positive := 256 * 1_024 * 1_024;
   Maximum_Archive_Output_Bytes : constant Positive := 256 * 1_024 * 1_024;
   --  Shared persistence, snapshot, and archive defaults.
end Ada_Quality.Resource_Limits;
