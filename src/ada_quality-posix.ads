with Interfaces.C;
with System;

--  Single typed Ada boundary for the small POSIX surface used by artifact and
--  coverage operations.  No other Ada unit should import libc directly.
package Ada_Quality.POSIX is
   use type Interfaces.C.int;
   subtype File_Descriptor is Interfaces.C.int;
   Invalid_Descriptor : constant File_Descriptor := -1;

   subtype Directory_Handle is System.Address;
   Null_Directory : constant Directory_Handle := System.Null_Address;

   function Open_Read_Nofollow
     (Path : Interfaces.C.char_array) return File_Descriptor
   with Import, Convention => C, External_Name => "ada_quality_open_read_nofollow";
   function Open_Child_Nofollow
     (Directory : File_Descriptor;
      Name      : Interfaces.C.char_array) return File_Descriptor
   with Import, Convention => C, External_Name => "ada_quality_open_child_nofollow";
   function Open_Directory_Nofollow
     (Path : Interfaces.C.char_array) return File_Descriptor
   with Import, Convention => C, External_Name => "ada_quality_open_directory_nofollow";
   function Create_Private
     (Path : Interfaces.C.char_array) return File_Descriptor
   with Import, Convention => C, External_Name => "ada_quality_create_private";
   function Create_Public
     (Path : Interfaces.C.char_array) return File_Descriptor
   with Import, Convention => C, External_Name => "ada_quality_create_public";
   function Create_Public_At
     (Directory : File_Descriptor;
      Name      : Interfaces.C.char_array) return File_Descriptor
   with Import, Convention => C, External_Name => "ada_quality_create_public_at";
   function Try_Lock_File
     (Path : Interfaces.C.char_array) return File_Descriptor
   with Import, Convention => C, External_Name => "ada_quality_try_lock_file";

   function Descriptor_Kind (Descriptor : File_Descriptor) return Interfaces.C.int
   with Import, Convention => C, External_Name => "ada_quality_descriptor_kind";
   function Read
     (Descriptor : File_Descriptor; Buffer : System.Address;
      Count : Interfaces.C.size_t) return Interfaces.C.long
   with Import, Convention => C, External_Name => "read";
   function Write
     (Descriptor : File_Descriptor; Buffer : System.Address;
      Count : Interfaces.C.size_t) return Interfaces.C.long
   with Import, Convention => C, External_Name => "write";
   function Close_Raw (Descriptor : File_Descriptor) return Interfaces.C.int
   with Import, Convention => C, External_Name => "close";
   function Close_Succeeded
     (Descriptor : in out File_Descriptor) return Boolean;
   --  Close Descriptor, invalidate it, and report whether close succeeded.

   procedure Close (Descriptor : in out File_Descriptor);
   --  Best-effort cleanup that always invalidates Descriptor.

   function Directory_Open (Descriptor : File_Descriptor) return Directory_Handle
   with Import, Convention => C, External_Name => "ada_quality_directory_open";
   function Directory_Next
     (Handle : Directory_Handle; Name : System.Address;
      Capacity : Interfaces.C.size_t) return Interfaces.C.int
   with Import, Convention => C, External_Name => "ada_quality_directory_next";
   function Directory_Close (Handle : Directory_Handle) return Interfaces.C.int
   with Import, Convention => C, External_Name => "ada_quality_directory_close";

   function Unlink_At
     (Directory : File_Descriptor; Name : Interfaces.C.char_array;
      Flags : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "unlinkat";
   function Link_At
     (Old_Directory : File_Descriptor; Old_Name : Interfaces.C.char_array;
      New_Directory : File_Descriptor; New_Name : Interfaces.C.char_array;
      Flags : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "linkat";
   function Process_Id return Interfaces.C.int
   with Import, Convention => C, External_Name => "getpid";
   function Signal_Process
     (Process : Interfaces.C.int;
      Signal  : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "kill";
   function Restore_Sigpipe_Default return Interfaces.C.int
   with Import, Convention => C,
     External_Name => "ada_quality_restore_sigpipe_default";
   function Make_Directory
     (Path : Interfaces.C.char_array;
      Mode : Interfaces.C.unsigned) return Interfaces.C.int
   with Import, Convention => C, External_Name => "mkdir";
   function Rename
     (Old_Path, New_Path : Interfaces.C.char_array) return Interfaces.C.int
   with Import, Convention => C, External_Name => "rename";
end Ada_Quality.POSIX;
