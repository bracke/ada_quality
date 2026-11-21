with Ada.Command_Line;
with Ada_Quality.CLI;
with Ada_Quality.POSIX;
with Interfaces.C;

procedure Ada_Quality_CLI is
   --  Application entry point that dispatches the CLI and applies its stable exit status.
   Sigpipe_Status : constant Interfaces.C.int :=
     Ada_Quality.POSIX.Restore_Sigpipe_Default;
   pragma Unreferenced (Sigpipe_Status);
   Code : constant Natural := Ada_Quality.CLI.Run;
begin
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Code));
end Ada_Quality_CLI;
