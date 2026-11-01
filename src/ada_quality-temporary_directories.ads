with Ada.Finalization;
with Ada.Strings.Unbounded;

--  Private, automatically cleaned temporary directories for isolated tool work.
package Ada_Quality.Temporary_Directories is
   --  Private owner-only temporary directories with automatic cleanup.
   Temporary_Directory_Error : exception;
   --  Raised when a private temporary directory cannot be allocated or secured.

   type Temporary_Directory is new Ada.Finalization.Limited_Controlled with private;
   --  Owner-only temporary directory that removes its tree during finalization.

   procedure Create (Item : in out Temporary_Directory; Prefix : String);
   --  Atomically allocate a unique mode-0700 directory.
   --  @param Item Directory owner to initialize.
   --  @param Prefix Human-readable, sanitized name prefix.

   procedure Cleanup (Item : in out Temporary_Directory);
   --  Remove the owned directory tree without following symbolic links.
   --  @param Item Directory owner to clean; inactive values are accepted.

   function Path (Item : Temporary_Directory) return String;
   --  Return the allocated directory path.
   --  @param Item Active directory owner.
   --  @return Absolute directory path.

   function Child (Item : Temporary_Directory; Name : String) return String;
   --  Construct a direct child path beneath the allocated directory.
   --  @param Item Active directory owner.
   --  @param Name Relative child name.
   --  @return Joined child path.

   function Is_Active (Item : Temporary_Directory) return Boolean;
   --  Test whether a directory is currently allocated.
   --  @param Item Directory owner to inspect.
   --  @return True while Item owns an allocated directory.

private
   type Temporary_Directory is new Ada.Finalization.Limited_Controlled with record
      Directory : Ada.Strings.Unbounded.Unbounded_String;
      Active    : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Temporary_Directory);
   --  Clean up the directory when its controlled owner leaves scope.
   --  @param Item Directory owner being finalized.
end Ada_Quality.Temporary_Directories;
