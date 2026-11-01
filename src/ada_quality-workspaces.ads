with Ada.Strings.Unbounded;
with Ada_Quality.Temporary_Directories;

--  Symlink-safe isolated staging for projects and recursive local dependencies.
package Ada_Quality.Workspaces is
   --  Symlink-safe isolated staging for projects and recursive local dependencies.
   Workspace_Error : exception;
   --  Raised when safe project staging cannot be completed.

   type Workspace is limited private;
   --  Isolated staged project tree and its private scratch directory.

   procedure Prepare (Item : in out Workspace; Source : String; Identity : String);
   --  Copy a project and recursive local pins into a symlink-safe private workspace.
   --  @param Item Workspace to initialize.
   --  @param Source Project root to stage.
   --  @param Identity Human-readable invocation identity used only as a name prefix.

   procedure Cleanup (Item : in out Workspace);
   --  Remove the private staged tree.
   --  @param Item Workspace to clean; inactive values are accepted.

   function Path (Item : Workspace) return String;
   --  Return the staged project root.
   --  @param Item Active workspace.
   --  @return Absolute staged project path.

   function Scratch_Path (Item : Workspace; Name : String) return String;
   --  Construct a scratch path beside the staged project inside the private directory.
   --  @param Item Active workspace.
   --  @param Name Relative scratch name.
   --  @return Absolute scratch path.

   function Is_Active (Item : Workspace) return Boolean;
   --  Test whether the workspace owns a staged tree.
   --  @param Item Workspace to inspect.
   --  @return True while Item is active.

private
   type Workspace is limited record
      Root    : Ada.Strings.Unbounded.Unbounded_String;
      Scratch : Ada_Quality.Temporary_Directories.Temporary_Directory;
   end record;
end Ada_Quality.Workspaces;
