# Project registry

Registration canonicalizes an existing non-symlink directory, requires `alire.toml`, and parses nonempty quoted name and version through `project_tools` TOML APIs. Active duplicates are rejected. IDs are stable, disable/enable changes eligibility, and removal is soft. Assessment start requires an active enabled project.
