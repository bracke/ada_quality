with Ada.Command_Line;
with Ada_Quality.CLI;

procedure Ada_Quality_CLI is
   --  Application entry point that dispatches the CLI and applies its stable exit status.
   Code : constant Natural := Ada_Quality.CLI.Run;
begin
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Code));
end Ada_Quality_CLI;
