# Project registry

Registration canonicalizes an existing non-symlink directory, requires a structurally valid `alire.toml`, and reads
nonempty top-level name and version values through the shared manifest boundary. Active duplicates are rejected. IDs
are stable, disable/enable changes eligibility, and removal is soft. Assessment start requires an active enabled
project.
