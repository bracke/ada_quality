# Workspace isolation

Every assessment copies the project into a unique temporary container, rejects symbolic links, omits generated
trees, and runs build/test/doc/proof/release tools there. From each `alire` state directory only the committed
`alire.lock` is retained; mutable settings, logs, flags, and build-hash inputs are regenerated in the stage. Local
dependencies are read only from Alire's `[[pins]]` entries and `[solution.state.link]` lockfile tables. Comments,
ordinary strings, multiline strings, and unrelated `path` keys cannot create dependencies. Normal whitespace,
quoted or bare `path` keys, single- and double-quoted values, and TOML Unicode escapes are supported. Relative
dependency targets are recursively copied into the
same container, while escaping, absolute, missing, and symbolic-link targets are rejected. Cleanup runs on success
and exceptions. Original Git status, when required by policy, and the source fingerprint are checked before and
after.
