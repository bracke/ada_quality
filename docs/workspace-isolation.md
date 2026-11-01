# Workspace isolation

Every assessment copies the project into a unique temporary container, rejects symbolic links, omits generated
trees, and runs build/test/doc/proof/release tools there. From each `alire` state directory only the committed
`alire.lock` is retained; mutable settings, logs, flags, and build-hash inputs are regenerated in the stage. Local
`path` keys from either the manifest or committed lockfile are tokenized outside TOML comments and strings; normal
whitespace plus single- and double-quoted values are supported. Relative dependency targets are recursively copied
into the same container, while escaping, absolute, missing, and symbolic-link targets are rejected. Cleanup runs on
success and exceptions. Original Git status, when required by policy, and the source fingerprint are checked before
and after.
